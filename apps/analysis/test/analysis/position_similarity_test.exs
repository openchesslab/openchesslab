defmodule Analysis.PositionSimilarityTest do
  use ExUnit.Case, async: true

  alias Analysis.PositionSimilarity
  alias Chess.Position

  defp digest_of(fen) do
    {:ok, %{position: position}} = Chess.Notation.FEN.parse(fen)
    PositionSimilarity.digest(position)
  end

  test "the starting position packs the expected digest" do
    digest = digest_of("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")

    assert digest.side_to_move == :white
    assert digest.castling == 15
    assert digest.open_files == 0
    assert digest.semi_open_white == 0
    assert digest.semi_open_black == 0

    # Material nibbles (white Q R B N P = slots 0..4): 1, 2, 2, 2, 8.
    key = digest.material_key
    assert rem(key, 16) == 1
    assert rem(div(key, 16), 16) == 2
    assert rem(div(key, 256), 16) == 2
    assert rem(div(key, 4096), 16) == 2
    assert rem(div(key, 65_536), 16) == 8
    # Black mirrors it (slots 5..9): the whole key is symmetric.
    assert rem(div(key, 1_048_576), 16) == 1
    assert rem(div(key, Bitwise.bsl(1, 36)), 16) == 8

    # Kings on e1 (file 4, rank 0) and e8 (file 4, rank 7):
    # 4 + 0*8 + 4*64 + 7*512.
    assert digest.king_key == 4 + 4 * 64 + 7 * 512
  end

  test "side to move, castling rights and file masks follow the position" do
    position =
      [side_to_move: :black, castling_rights: MapSet.new([:white_kingside, :black_queenside])]
      |> Position.new()
      |> Position.put_piece(Chess.Square.from_algebraic("e1"), {:white, :king})
      |> Position.put_piece(Chess.Square.from_algebraic("e8"), {:black, :king})
      |> Position.put_piece(Chess.Square.from_algebraic("a2"), {:white, :pawn})
      |> Position.put_piece(Chess.Square.from_algebraic("b7"), {:black, :pawn})

    digest = PositionSimilarity.digest(position)

    assert digest.side_to_move == :black
    # K=8, q=1.
    assert digest.castling == 9

    # a-file: white pawn only -> Black's semi-open file (bit 0).
    assert Bitwise.band(digest.semi_open_black, 0b00000001) == 1
    # b-file: black pawn only -> White's semi-open file (bit 1).
    assert Bitwise.band(digest.semi_open_white, 0b00000010) == 2
    # c-h hold no pawns at all -> open.
    assert digest.open_files == 0b11111100
  end

  test "material keys distinguish multisets and stay stable" do
    rook = digest_of("4k3/8/8/8/8/8/8/R3K3 w Q - 0 1")
    knight = digest_of("4k3/8/8/8/8/8/8/N3K3 w - - 0 1")

    refute rook.material_key == knight.material_key
    # Same multiset, different square: identical key (it is a count, not a map).
    assert rook.material_key == digest_of("4k3/8/8/8/8/8/8/4K1R1 w - - 0 1").material_key
  end
end
