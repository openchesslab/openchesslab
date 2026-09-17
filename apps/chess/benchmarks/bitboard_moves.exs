alias Chess.Bitboard
alias Chess.Move
alias Chess.Position

defmodule BenchmarkHelpers do
  def square(algebraic), do: Chess.Square.from_algebraic(algebraic)

  def middlegame_position do
    Position.starting_position()
    |> apply_move("e2", "e4")
    |> apply_move("e7", "e5")
    |> apply_move("g1", "f3")
    |> apply_move("b8", "c6")
    |> apply_move("f1", "b5")
    |> apply_move("a7", "a6")
    |> apply_move("b5", "a4")
    |> apply_move("g8", "f6")
    |> apply_move("e1", "g1")
    |> apply_move("f8", "e7")
  end

  def apply_move(position, from, to) do
    {:ok, position} =
      Position.apply_move(
        position,
        Move.new(square(from), square(to))
      )

    position
  end
end

starting_position = Position.starting_position()
middlegame_position = BenchmarkHelpers.middlegame_position()

starting_bitboard = Bitboard.from_position(starting_position)
middlegame_bitboard = Bitboard.from_position(middlegame_position)

starting_square = BenchmarkHelpers.square("e4")
middlegame_square = BenchmarkHelpers.square("e4")

Benchee.run(
  %{
    "start: pseudo_moves" => fn ->
      Bitboard.pseudo_moves(starting_bitboard, :white)
    end,
    "middlegame: pseudo_moves" => fn ->
      Bitboard.pseudo_moves(middlegame_bitboard, :white)
    end,
    "start: pieces" => fn ->
      Bitboard.pieces(starting_bitboard)
    end,
    "middlegame: pieces" => fn ->
      Bitboard.pieces(middlegame_bitboard)
    end,
    "start: get" => fn ->
      Bitboard.get(starting_bitboard, starting_square)
    end,
    "middlegame: get" => fn ->
      Bitboard.get(middlegame_bitboard, middlegame_square)
    end,
    "start: attacked?" => fn ->
      Bitboard.attacked?(starting_bitboard, :black, starting_square)
    end,
    "middlegame: attacked?" => fn ->
      Bitboard.attacked?(middlegame_bitboard, :black, middlegame_square)
    end
  },
  warmup: 2,
  time: 5,
  memory_time: 2,
  parallel: 1
)
