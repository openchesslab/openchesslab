defmodule Chess.PerftTest do
  @moduledoc """
  Perft against the published CPW suite counts (first five positions;
  cross-checked with the python-chess reference engine, which also supplied
  the last position's counts). These anchor the gameplay engine's move
  generation absolutely (the duplicate en-passant-target move found by the
  features differential harness showed up here as +1 at Kiwipete depth 3).
  """

  use ExUnit.Case, async: false

  alias Chess.Notation.FEN
  alias Chess.Notation.UCI
  alias Chess.Position

  @perft_suite [
    {"startpos", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", [20, 400, 8902]},
    {"kiwipete", "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
     [48, 2039, 97_862]},
    {"ep-and-pins", "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", [14, 191, 2812]},
    {"castling-gauntlet", "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
     [6, 264, 9467]},
    {"promotion-pressure", "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
     [44, 1486, 62_379]},
    {"midgame", "r4rk1/1pp1qppp/p1np1n2/8/2BPP3/P1N2N2/1P2QPPP/R4RK1 w - - 0 10",
     [44, 1591, 68_174]}
  ]

  test "published node counts hold" do
    divergences =
      for {name, fen, counts} <- @perft_suite,
          {expected, depth} <- Enum.with_index(counts, 1),
          actual = perft(fen, depth),
          actual != expected do
        {name, depth, expected, actual}
      end

    assert divergences == []
  end

  test "no duplicated legal moves onto the en passant target square" do
    # After 1.Bb5 c5 in the Kiwipete position the en passant target c6 is
    # reachable by the b5 bishop as a quiet move and by the d5 pawn as the
    # en passant capture. Both exist exactly once.
    {:ok, %{position: position}} =
      FEN.parse("r3k2r/p2pqpb1/bn2pnp1/1BpPN3/1p2P3/2N2Q1p/PPP1BPPP/R3K2R w KQkq c6 0 2")

    moves =
      position
      |> Position.legal_moves()
      |> Enum.map(&UCI.format/1)

    assert moves == Enum.uniq(moves)
    assert Enum.count(moves, &(&1 == "b5c6")) == 1
    assert Enum.count(moves, &(&1 == "d5c6")) == 1
  end

  test "a rook on e1 does not create phantom castling moves" do
    # With the king on g1 and a rook on e1, "e1c1" is a plain rook move and
    # must not also appear as a castling candidate.
    {:ok, %{position: position}} = FEN.parse("6k1/8/8/8/8/8/8/4R1K1 w - - 0 1")

    moves =
      position
      |> Position.legal_moves()
      |> Enum.map(&UCI.format/1)

    assert moves == Enum.uniq(moves)
    assert Enum.count(moves, &(&1 == "e1c1")) == 1
    refute "e1g1" in moves
  end

  test "a rook capturing away from its home square loses the castling right" do
    # The capture path updated rights for the captured piece but not for a
    # rook leaving home by capturing (found by the differential harness).
    {:ok, %{position: position}} = FEN.parse("r3kN1r/8/8/8/8/8/8/4K3 b kq - 0 1")

    move = position |> Position.legal_moves() |> Enum.find(&(UCI.format(&1) == "h8f8"))
    assert {:ok, next} = Position.apply_move(position, move)
    assert next.castling_rights == MapSet.new([:black_queenside])
  end

  defp perft(fen, depth) do
    {:ok, %{position: position}} = FEN.parse(fen)
    do_perft(position, depth)
  end

  defp do_perft(_position, 0), do: 1

  defp do_perft(position, depth) do
    position
    |> Position.legal_moves()
    |> Enum.reduce(0, fn move, acc ->
      {:ok, next} = Position.apply_move(position, move)
      acc + do_perft(next, depth - 1)
    end)
  end
end
