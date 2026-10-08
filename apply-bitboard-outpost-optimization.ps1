# Apply only to OpenChessLab main at 5d259f5.
# No database changes. No existing source files are overwritten if dirty.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$expectedCommit = '5d259f550b86b57c443c38170ad5bc307d65ea2b'
$sourceRelative = 'apps/chess/lib/chess/position_properties.ex'
$testRelative = 'apps/chess/test/chess/position_outposts_bitboard_test.exs'

$actualCommit = (& git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $actualCommit -ne $expectedCommit) {
    throw "Expected HEAD $expectedCommit; found $actualCommit."
}

$changes = @(& git status --porcelain -- $sourceRelative $testRelative)
if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect Git working tree.' }
if ($changes.Count -ne 0) { throw "Target paths are already modified: $($changes -join '; ')" }
if (Test-Path -LiteralPath $testRelative) { throw "$testRelative already exists." }

$sourcePath = (Join-Path (Get-Location).Path $sourceRelative)
$testPath = (Join-Path (Get-Location).Path $testRelative)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$original = [System.IO.File]::ReadAllText($sourcePath)
$hadCRLF = $original.Contains("`r`n")
$code = $original.Replace("`r`n", "`n")

function Replace-ExactlyOnce {
    param([string] $Source, [string] $Old, [string] $New, [string] $Description)
    $first = $Source.IndexOf($Old, [System.StringComparison]::Ordinal)
    if ($first -lt 0) { throw "Missing code anchor: $Description" }
    $next = $Source.IndexOf($Old, $first + $Old.Length, [System.StringComparison]::Ordinal)
    if ($next -ge 0) { throw "Repeated code anchor: $Description" }
    return $Source.Substring(0, $first) + $New + $Source.Substring($first + $Old.Length)
}

$old = @'
  @files [:a, :b, :c, :d, :e, :f, :g, :h]
'@
$new = @'
  @files [:a, :b, :c, :d, :e, :f, :g, :h]

  @board_mask 0xFFFFFFFFFFFFFFFF
  @not_a_file 0xFEFEFEFEFEFEFEFE
  @not_h_file 0x7F7F7F7F7F7F7F7F
  @white_opponent_half 0xFFFFFFFF00000000
  @black_opponent_half 0x00000000FFFFFFFF
'@
$code = Replace-ExactlyOnce -Source $code -Description 'bitboard mask constants' -Old $old -New $new

$old = @'
  @spec outposts(Position.t()) :: %{white: [0..63], black: [0..63]}
  def outposts(%Position{} = position) do
    board = Bitboard.from_position(position)

    %{
      white: outposts_for(board, :white),
      black: outposts_for(board, :black)
    }
  end
'@
$new = @'
  @spec outposts(Position.t()) :: %{white: [0..63], black: [0..63]}
  def outposts(%Position{} = position) do
    board = Bitboard.from_position(position)

    white_control = pawn_attack_mask_from_pawns(board.white_pawns, :white)
    black_control = pawn_attack_mask_from_pawns(board.black_pawns, :black)

    white_outposts =
      board.white_knights
      |> Bitwise.band(@white_opponent_half)
      |> Bitwise.band(white_control)
      |> Bitwise.band(Bitwise.bnot(black_control))
      |> squares_in()

    black_outposts =
      board.black_knights
      |> Bitwise.band(@black_opponent_half)
      |> Bitwise.band(black_control)
      |> Bitwise.band(Bitwise.bnot(white_control))
      |> squares_in()

    %{white: white_outposts, black: black_outposts}
  end
'@
$code = Replace-ExactlyOnce -Source $code -Description 'public outposts function' -Old $old -New $new

$old = @'
  defp outposts_for(board, color) do
    enemy_pawn_attacks = pawn_attack_mask(board, opposite(color))
    own_pawn_attacks = pawn_attack_mask(board, color)

    board
    |> Bitboard.pieces()
    |> Enum.filter(fn {_square, piece} -> piece == {color, :knight} end)
    |> Enum.map(fn {square, _piece} -> square end)
    |> Enum.filter(&opponent_half?(color, &1))
    |> Enum.filter(fn square ->
      not attacked_by?(enemy_pawn_attacks, square) and
        attacked_by?(own_pawn_attacks, square)
    end)
    |> Enum.sort()
  end
'@
$new = ''
$code = Replace-ExactlyOnce -Source $code -Description 'obsolete enumerating outposts implementation' -Old $old -New $new

$old = @'
  defp pawn_attack_mask(board, color) do
'@
$new = @'
  defp pawn_attack_mask_from_pawns(pawns, :white) do
    left = Bitwise.bsl(Bitwise.band(pawns, @not_a_file), 7)
    right = Bitwise.bsl(Bitwise.band(pawns, @not_h_file), 9)

    Bitwise.band(Bitwise.bor(left, right), @board_mask)
  end

  defp pawn_attack_mask_from_pawns(pawns, :black) do
    left = Bitwise.bsr(Bitwise.band(pawns, @not_a_file), 9)
    right = Bitwise.bsr(Bitwise.band(pawns, @not_h_file), 7)

    Bitwise.bor(left, right)
  end

  defp pawn_attack_mask(board, color) do
'@
$code = Replace-ExactlyOnce -Source $code -Description 'pawn control mask functions' -Old $old -New $new

$testCode = @'
defmodule Chess.PositionOutpostsBitboardTest do
  use ExUnit.Case, async: true

  alias Chess.Position
  alias Chess.PositionProperties
  alias Chess.Square

  test "finds pawn-defended knight outposts of both colors" do
    position =
      Position.new()
      |> place("h5", {:white, :knight})
      |> place("g4", {:white, :pawn})
      |> place("a4", {:black, :knight})
      |> place("b5", {:black, :pawn})

    assert PositionProperties.outposts(position) == %{
             white: [square("h5")],
             black: [square("a4")]
           }
  end

  test "rejects both outposts when enemy pawns attack their squares" do
    position =
      Position.new()
      |> place("h5", {:white, :knight})
      |> place("g4", {:white, :pawn})
      |> place("a4", {:black, :knight})
      |> place("b5", {:black, :pawn})
      |> place("g6", {:black, :pawn})
      |> place("b3", {:white, :pawn})

    assert PositionProperties.outposts(position) == %{white: [], black: []}
  end

  test "rejects unsupported knights and knights on their own half" do
    position =
      Position.new()
      |> place("e5", {:white, :knight})
      |> place("h4", {:white, :knight})
      |> place("g3", {:white, :pawn})
      |> place("a5", {:black, :knight})
      |> place("b6", {:black, :pawn})

    assert PositionProperties.outposts(position) == %{white: [], black: []}
  end

  test "returns ordered square lists with no file-edge wraparound" do
    position =
      Position.new()
      |> place("h5", {:white, :knight})
      |> place("g4", {:white, :pawn})
      |> place("e5", {:white, :knight})
      |> place("d4", {:white, :pawn})
      |> place("a6", {:black, :pawn})

    assert PositionProperties.outposts(position) == %{
             white: [square("e5"), square("h5")],
             black: []
           }
  end

  defp place(position, algebraic, piece) do
    Position.put_piece(position, square(algebraic), piece)
  end

  defp square(algebraic), do: Square.from_algebraic(algebraic)
end
'@

if ($hadCRLF) { $code = $code.Replace("`n", "`r`n") }
[System.IO.File]::WriteAllText($sourcePath, $code, $utf8NoBom)
[System.IO.File]::WriteAllText($testPath, $testCode + "`n", $utf8NoBom)

Write-Host "Updated: $sourceRelative"
Write-Host "Created: $testRelative"
Write-Host 'Next: mix format; mix test apps/chess/test/chess/position_outposts_bitboard_test.exs; mix test'
