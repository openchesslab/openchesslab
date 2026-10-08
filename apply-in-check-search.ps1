$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$expectedCommit = "cad6073dd45112095914e9bc4287c18f9b8219cc"
$codecPath = "apps/analysis/lib/analysis/position_property_key_codec.ex"
$storePath = "apps/analysis/lib/analysis/position_store.ex"
$unitPath = "apps/analysis/test/analysis/position_in_check_test.exs"
$integrationPath = "apps/analysis/test/integration/postgres_position_in_check_test.exs"
$paths = @($codecPath, $storePath, $unitPath, $integrationPath)

$head = (git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $head -ne $expectedCommit) {
    throw "Expected HEAD $expectedCommit, got $head"
}

$branch = (git branch --show-current).Trim()
if ($LASTEXITCODE -ne 0 -or $branch -ne "main") {
    throw "Expected branch main, got $branch"
}

$root = (git rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0) {
    throw "Cannot determine repository root"
}

$dirty = @(git status --porcelain -- $paths | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_)
})
if ($LASTEXITCODE -ne 0 -or $dirty.Count -gt 0) {
    throw "Target files contain changes: $($dirty -join '; ')"
}

$codecFile = Join-Path $root $codecPath
$storeFile = Join-Path $root $storePath
$unitFile = Join-Path $root $unitPath
$integrationFile = Join-Path $root $integrationPath

if ((Test-Path -LiteralPath $unitFile) -or (Test-Path -LiteralPath $integrationFile)) {
    throw "Target test file already exists; refusing to overwrite"
}

function Replace-ExactlyOnce {
    param(
        [string]$Label,
        [string]$Content,
        [string]$Original,
        [string]$Replacement
    )

    $matches = [regex]::Matches($Content, [regex]::Escape($Original)).Count
    if ($matches -ne 1) {
        throw "${Label}: expected exactly one replacement anchor, found $matches"
    }
    return $Content.Replace($Original, $Replacement)
}

$codec = [System.IO.File]::ReadAllText($codecFile).Replace("`r`n", "`n")
$store = [System.IO.File]::ReadAllText($storeFile).Replace("`r`n", "`n")

$codecOriginal = @'
  def encode(:material, %{white: white, black: black}) when is_map(white) and is_map(black) do
'@
$codecReplacement = @'
  def encode(:in_check, color) do
    case Map.fetch(@color_ids, color) do
      {:ok, color_id} ->
        {:ok, <<6::unsigned-8, color_id::unsigned-8>>}

      :error ->
        {:error, :invalid_in_check}
    end
  end

  def encode(:material, %{white: white, black: black}) when is_map(white) and is_map(black) do
'@
$codec = Replace-ExactlyOnce "PositionPropertyKeyCodec" $codec $codecOriginal $codecReplacement

$storeChecksOriginal = @'
    outposts = PositionProperties.outposts(position)

    properties =
'@
$storeChecksReplacement = @'
    outposts = PositionProperties.outposts(position)

    checks = PositionProperties.in_check(position)

    properties =
'@
$store = Replace-ExactlyOnce "PositionStore check facts" $store $storeChecksOriginal $storeChecksReplacement

$storePropertiesOriginal = @'
        ) ++
        [
          {
            :material,
            PositionProperties.material(position)
          },
          {:side_to_move, position.side_to_move}
        ]
'@
$storePropertiesReplacement = @'
        ) ++
        Enum.flat_map(
          [:white, :black],
          fn color ->
            if Map.fetch!(checks, color) do
              [{:in_check, color}]
            else
              []
            end
          end
        ) ++
        [
          {
            :material,
            PositionProperties.material(position)
          },
          {:side_to_move, position.side_to_move}
        ]
'@
$store = Replace-ExactlyOnce "PositionStore feature list" $store $storePropertiesOriginal $storePropertiesReplacement

$unit = @'
defmodule Analysis.PositionInCheckTest do
  use ExUnit.Case, async: true

  alias Analysis.PositionPropertyKeyCodec

  test "encodes a checked king per color" do
    assert PositionPropertyKeyCodec.encode(:in_check, :white) ==
             {:ok, <<6, 0>>}

    assert PositionPropertyKeyCodec.encode(:in_check, :black) ==
             {:ok, <<6, 1>>}
  end

  test "rejects invalid checked-king search keys" do
    for value <- [:red, :both, nil, false, 0, "white", {:white, true}] do
      assert PositionPropertyKeyCodec.encode(:in_check, value) ==
               {:error, :invalid_in_check}
    end
  end

  test "check status keys differ from existing position property keys" do
    {:ok, white_check} = PositionPropertyKeyCodec.encode(:in_check, :white)
    {:ok, black_check} = PositionPropertyKeyCodec.encode(:in_check, :black)
    {:ok, white_turn} = PositionPropertyKeyCodec.encode(:side_to_move, :white)
    {:ok, white_outpost} = PositionPropertyKeyCodec.encode(:outposts, {:white, 36})

    assert MapSet.size(MapSet.new([white_check, black_check, white_turn, white_outpost])) == 4
  end
end
'@

$integration = @'
defmodule Analysis.PostgresPositionInCheckTest do
  use ExUnit.Case, async: false

  alias Analysis.PositionPropertyKeyCodec
  alias Analysis.PositionQuery, as: Query
  alias Analysis.PositionStore
  alias Chess.Position
  alias Chess.Square
  alias OpenChessLab.Repo

  @moduletag postgres: true

  setup do
    Repo.query!(
      """
      TRUNCATE TABLE
        position_features,
        positions
      RESTART IDENTITY
      CASCADE
      """,
      []
    )

    :ok
  end

  test "indexes only the kings that are in check, including hypothetical double checks" do
    white_checked =
      Position.new(side_to_move: :white)
      |> place("e1", {:white, :king})
      |> place("h8", {:black, :king})
      |> place("e4", {:black, :rook})

    black_checked =
      Position.new(side_to_move: :black)
      |> place("a1", {:white, :king})
      |> place("e8", {:black, :king})
      |> place("e5", {:white, :rook})

    both_checked =
      Position.new(side_to_move: :white)
      |> place("e1", {:white, :king})
      |> place("e8", {:black, :king})
      |> place("e4", {:black, :rook})
      |> place("e5", {:white, :rook})

    neither_checked =
      Position.new(side_to_move: :black)
      |> place("a1", {:white, :king})
      |> place("h8", {:black, :king})

    assert {:ok, [white_id, black_id, both_id, safe_id]} =
             PositionStore.append_many([
               white_checked,
               black_checked,
               both_checked,
               neither_checked
             ])

    assert {:ok, %PositionStore.Page{entries: [^white_id, ^both_id], next: nil}} =
             PositionStore.page(Query.property(:in_check, :white), limit: 10)

    assert {:ok, %PositionStore.Page{entries: [^black_id, ^both_id], next: nil}} =
             PositionStore.page(Query.property(:in_check, :black), limit: 10)

    {:ok, white_key} = PositionPropertyKeyCodec.encode(:in_check, :white)
    {:ok, black_key} = PositionPropertyKeyCodec.encode(:in_check, :black)

    assert [[both_properties]] =
             Repo.query!(
               "SELECT properties FROM position_features WHERE position_id = $1",
               [both_id]
             ).rows

    assert white_key in both_properties
    assert black_key in both_properties

    assert [[safe_properties]] =
             Repo.query!(
               "SELECT properties FROM position_features WHERE position_id = $1",
               [safe_id]
             ).rows

    refute white_key in safe_properties
    refute black_key in safe_properties
  end

  test "pages checked positions with side to move and supports negation" do
    first =
      Position.new(side_to_move: :white)
      |> place("e1", {:white, :king})
      |> place("h8", {:black, :king})
      |> place("e4", {:black, :rook})

    second = place(first, "a2", {:white, :pawn})
    black_turn = %{first | side_to_move: :black}
    safe = Position.new(side_to_move: :white)

    first_id = PositionStore.append(first)
    second_id = PositionStore.append(second)
    black_id = PositionStore.append(black_turn)
    safe_id = PositionStore.append(safe)

    query =
      Query.all([
        Query.property(:in_check, :white),
        Query.property(:side_to_move, :white)
      ])

    assert {:ok, %PositionStore.Page{entries: [^first_id], next: cursor}} =
             PositionStore.page(query, limit: 1)

    assert %PositionStore.Cursor{} = cursor

    assert {:ok, %PositionStore.Page{entries: [^second_id], next: nil}} =
             PositionStore.page(query, limit: 1, cursor: cursor)

    assert {:ok, %PositionStore.Page{entries: [^safe_id], next: nil}} =
             PositionStore.page(
               Query.all([
                 Query.negate(Query.property(:in_check, :white)),
                 Query.property(:side_to_move, :white)
               ]),
               limit: 10
             )

    refute black_id in [first_id, second_id]
  end

  defp place(position, algebraic, piece) do
    Position.put_piece(position, Square.from_algebraic(algebraic), piece)
  end
end
'@

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($codecFile, $codec, $utf8NoBom)
[System.IO.File]::WriteAllText($storeFile, $store, $utf8NoBom)
[System.IO.File]::WriteAllText($unitFile, ($unit + "`n"), $utf8NoBom)
[System.IO.File]::WriteAllText($integrationFile, ($integration + "`n"), $utf8NoBom)

Write-Host "Added checked-king position search to these four files:"
$paths | ForEach-Object { Write-Host "  $_" }
Write-Host "Run mix format and tests before committing."
