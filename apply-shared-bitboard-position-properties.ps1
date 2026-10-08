# Run from the OpenChessLab repository root.
# Requires clean target files and exact starting commit 7af09423cee508449f9651c46e54325b4f614f58.
# Does not access PostgreSQL or modify existing stored data.
$ErrorActionPreference = 'Stop'

$expectedCommit = '7af09423cee508449f9651c46e54325b4f614f58'
$actualCommit = (& git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $actualCommit -ne $expectedCommit) {
    throw "Expected HEAD $expectedCommit, got $actualCommit."
}

$root = (& git rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0 -or -not $root) { throw 'Run inside the OpenChessLab repository.' }
Set-Location $root

$paths = @(
    'apps/chess/lib/chess/position_properties.ex',
    'apps/analysis/lib/analysis/position_store.ex',
    'apps/analysis/benchmarks/position_property_cost.exs'
)
$newTestPath = 'apps/chess/test/chess/position_properties_bitboard_test.exs'

foreach ($relativePath in $paths) {
    $changes = @(& git status --porcelain -- $relativePath)
    if ($LASTEXITCODE -ne 0 -or $changes.Count -gt 0) {
        throw "Target file has local modifications: $relativePath"
    }
    if (-not (Test-Path -LiteralPath $relativePath -PathType Leaf)) {
        throw "Missing target file: $relativePath"
    }
}
if (Test-Path -LiteralPath $newTestPath) {
    throw "Test file already exists: $newTestPath"
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
$contents = @{}
foreach ($relativePath in $paths) {
    $absolutePath = Join-Path $root $relativePath
    $contents[$relativePath] = [System.IO.File]::ReadAllText($absolutePath)
}

function Replace-ExactlyOnce {
    param([string] $Path, [string] $Old, [string] $New)
    $source = $script:contents[$Path]
    $normalized = $source.Replace("`r`n", "`n")
    $count = ([regex]::Matches($normalized, [regex]::Escape($Old))).Count
    if ($count -ne 1) {
        throw "Expected exactly one replacement anchor in $Path, found $count."
    }
    $updated = $normalized.Replace($Old, $New)
    if ($source.Contains("`r`n")) { $updated = $updated.Replace("`n", "`r`n") }
    $script:contents[$Path] = $updated
}

$chessFile = 'apps/chess/lib/chess/position_properties.ex'
Replace-ExactlyOnce -Path $chessFile -Old @'
  @spec semi_open_files(Position.t()) :: %{white: [atom()], black: [atom()]}
  def semi_open_files(%Position{} = position) do
    board = Bitboard.from_position(position)

    %{
      white: semi_open_files_for(board, :white),
      black: semi_open_files_for(board, :black)
    }
  end
'@ -New @'
  @spec semi_open_files(Position.t() | Bitboard.t()) :: %{white: [atom()], black: [atom()]}
  def semi_open_files(%Position{} = position) do
    position
    |> Bitboard.from_position()
    |> semi_open_files()
  end

  def semi_open_files(%Bitboard{} = board) do
    %{
      white: semi_open_files_for(board, :white),
      black: semi_open_files_for(board, :black)
    }
  end
'@

Replace-ExactlyOnce -Path $chessFile -Old @'
  @spec outposts(Position.t()) :: %{white: [0..63], black: [0..63]}
  def outposts(%Position{} = position) do
    board = Bitboard.from_position(position)

    white_control = pawn_attack_mask_from_pawns(board.white_pawns, :white)
'@ -New @'
  @spec outposts(Position.t() | Bitboard.t()) :: %{white: [0..63], black: [0..63]}
  def outposts(%Position{} = position) do
    position
    |> Bitboard.from_position()
    |> outposts()
  end

  def outposts(%Bitboard{} = board) do
    white_control = pawn_attack_mask_from_pawns(board.white_pawns, :white)
'@

$storeFile = 'apps/analysis/lib/analysis/position_store.ex'
Replace-ExactlyOnce -Path $storeFile -Old @'
  alias Analysis.PositionQueryNormalizer
  alias Chess.PawnStructure
'@ -New @'
  alias Analysis.PositionQueryNormalizer
  alias Chess.Bitboard
  alias Chess.PawnStructure
'@

Replace-ExactlyOnce -Path $storeFile -Old @'
  defp encoded_properties(%Position{} = position) do
    semi_open_files =
      PositionProperties.semi_open_files(position)

    outposts = PositionProperties.outposts(position)
'@ -New @'
  defp encoded_properties(%Position{} = position) do
    board = Bitboard.from_position(position)

    semi_open_files = PositionProperties.semi_open_files(board)

    outposts = PositionProperties.outposts(board)
'@

Replace-ExactlyOnce -Path $storeFile -Old @'
        PositionProperties.open_files(position),
'@ -New @'
        PositionProperties.open_files(board),
'@

Replace-ExactlyOnce -Path $storeFile -Old @'
            PositionProperties.material(position)
'@ -New @'
            PositionProperties.material(board)
'@

$benchFile = 'apps/analysis/benchmarks/position_property_cost.exs'
Replace-ExactlyOnce -Path $benchFile -Old @'
      {"combined derivation", &combined_score/1}
'@ -New @'
      {"combined separate boards", &combined_score/1},
      {"combined shared bitboard", &combined_shared_bitboard_score/1}
'@

Replace-ExactlyOnce -Path $benchFile -Old @'
    Enum.each(stages, fn {name, fun} ->
      profile_stage(name, fun, positions, count, runs)
    end)
'@ -New @'
    unless Enum.all?(positions, fn position ->
             combined_score(position) == combined_shared_bitboard_score(position)
           end) do
      raise "Shared-bitboard derivation changed the result checksum"
    end

    Enum.each(stages, fn {name, fun} ->
      profile_stage(name, fun, positions, count, runs)
    end)
'@

Replace-ExactlyOnce -Path $benchFile -Old @'
  defp bool_count(true), do: 1
'@ -New @'
  defp combined_shared_bitboard_score(position) do
    board = Bitboard.from_position(position)
    open = PositionProperties.open_files(board)
    semi = PositionProperties.semi_open_files(board)
    outposts = PositionProperties.outposts(board)
    checked = PositionProperties.in_check(position)
    material = PositionProperties.material(board)

    length(open) +
      length(semi.white) + length(semi.black) +
      length(outposts.white) + length(outposts.black) +
      bool_count(checked.white) + bool_count(checked.black) +
      material.white.pawn + material.black.pawn +
      MapSet.size(position.castling_rights) +
      bool_count(not is_nil(position.en_passant))
  end

  defp bool_count(true), do: 1
'@

$testContent = @'
defmodule Chess.PositionPropertiesBitboardTest do
  use ExUnit.Case, async: true

  alias Chess.Bitboard
  alias Chess.Position
  alias Chess.PositionProperties
  alias Chess.Square

  test "search-related features match between position and shared bitboard inputs" do
    for position <- sample_positions() do
      board = Bitboard.from_position(position)

      assert PositionProperties.open_files(board) ==
               PositionProperties.open_files(position)

      assert PositionProperties.semi_open_files(board) ==
               PositionProperties.semi_open_files(position)

      assert PositionProperties.outposts(board) ==
               PositionProperties.outposts(position)

      assert PositionProperties.material(board) ==
               PositionProperties.material(position)
    end
  end

  test "both colors' pawn-defended outposts and semi-open files survive shared board use" do
    position =
      Position.new()
      |> place("d4", {:white, :pawn})
      |> place("e5", {:white, :knight})
      |> place("e6", {:black, :pawn})
      |> place("b5", {:black, :pawn})
      |> place("a4", {:black, :knight})

    board = Bitboard.from_position(position)

    assert PositionProperties.outposts(board).white == [square("e5")]
    assert PositionProperties.outposts(board).black == [square("a4")]
    assert :e in PositionProperties.semi_open_files(board).white
    assert :d in PositionProperties.semi_open_files(board).black
  end

  defp sample_positions do
    [
      Position.new(),
      Position.starting_position(),
      Position.new()
      |> place("h5", {:white, :knight})
      |> place("g4", {:white, :pawn})
      |> place("a4", {:black, :knight})
      |> place("b5", {:black, :pawn}),
      Position.new()
      |> place("e5", {:white, :knight})
      |> place("d4", {:white, :pawn})
      |> place("f6", {:black, :pawn}),
      Position.new()
      |> place("e1", {:white, :king})
      |> place("e8", {:black, :king})
      |> place("d4", {:white, :pawn})
      |> place("e5", {:black, :pawn}),
      Position.new()
      |> place("a1", {:white, :rook})
      |> place("h8", {:black, :queen})
    ]
  end

  defp place(position, algebraic, piece) do
    Position.put_piece(position, square(algebraic), piece)
  end

  defp square(algebraic), do: Square.from_algebraic(algebraic)
end
'@

# Preflight completed: write all target files only after verifying all anchors.
foreach ($relativePath in $paths) {
    $absolutePath = Join-Path $root $relativePath
    [System.IO.File]::WriteAllText($absolutePath, $contents[$relativePath], $utf8)
}
[System.IO.File]::WriteAllText((Join-Path $root $newTestPath), ($testContent + "`n"), $utf8)

Write-Host 'Shared-bitboard refactor applied. Run mix format and tests before committing.'
