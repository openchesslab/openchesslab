alias Chess.Bitboard
alias Chess.Position
alias Chess.Square

board =
  Position.starting_position()
  |> Bitboard.from_position()

occupied = [
  Square.from_algebraic("a1"),
  Square.from_algebraic("e1"),
  Square.from_algebraic("d1"),
  Square.from_algebraic("e2")
]

empty = [
  Square.from_algebraic("a3"),
  Square.from_algebraic("e3"),
  Square.from_algebraic("d4"),
  Square.from_algebraic("e4")
]

Benchee.run(
  %{
    "occupied" => fn ->
      Enum.each(occupied, &Bitboard.get(board, &1))
    end,
    "empty" => fn ->
      Enum.each(empty, &Bitboard.get(board, &1))
    end
  },
  warmup: 2,
  time: 5,
  memory_time: 2,
  parallel: 1,
  print: [fast_warning: false]
)
