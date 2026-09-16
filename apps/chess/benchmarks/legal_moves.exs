alias Chess.Move
alias Chess.Position

defmodule BenchmarkHelpers do
  def square(algebraic), do: Chess.Square.from_algebraic(algebraic)
end

position =
  Position.starting_position()
  |> then(fn position ->
    {:ok, position} =
      Position.apply_move(
        position,
        Move.new(BenchmarkHelpers.square("e2"), BenchmarkHelpers.square("e4"))
      )

    {:ok, position} =
      Position.apply_move(
        position,
        Move.new(BenchmarkHelpers.square("e7"), BenchmarkHelpers.square("e5"))
      )

    {:ok, position} =
      Position.apply_move(
        position,
        Move.new(BenchmarkHelpers.square("g1"), BenchmarkHelpers.square("f3"))
      )

    {:ok, position} =
      Position.apply_move(
        position,
        Move.new(BenchmarkHelpers.square("b8"), BenchmarkHelpers.square("c6"))
      )

    {:ok, position} =
      Position.apply_move(
        position,
        Move.new(BenchmarkHelpers.square("f1"), BenchmarkHelpers.square("b5"))
      )

    {:ok, position} =
      Position.apply_move(
        position,
        Move.new(BenchmarkHelpers.square("a7"), BenchmarkHelpers.square("a6"))
      )

    {:ok, position} =
      Position.apply_move(
        position,
        Move.new(BenchmarkHelpers.square("b5"), BenchmarkHelpers.square("a4"))
      )

    {:ok, position} =
      Position.apply_move(
        position,
        Move.new(BenchmarkHelpers.square("g8"), BenchmarkHelpers.square("f6"))
      )

    {:ok, position} =
      Position.apply_move(
        position,
        Move.new(BenchmarkHelpers.square("e1"), BenchmarkHelpers.square("g1"))
      )

    {:ok, position} =
      Position.apply_move(
        position,
        Move.new(BenchmarkHelpers.square("f8"), BenchmarkHelpers.square("e7"))
      )

    position
  end)

check_position =
  Position.new(side_to_move: :white)
  |> Position.put_piece(BenchmarkHelpers.square("e1"), {:white, :king})
  |> Position.put_piece(BenchmarkHelpers.square("a1"), {:white, :rook})
  |> Position.put_piece(BenchmarkHelpers.square("e2"), {:white, :pawn})
  |> Position.put_piece(BenchmarkHelpers.square("e8"), {:black, :rook})
  |> Position.put_piece(BenchmarkHelpers.square("a8"), {:black, :king})

Benchee.run(
  %{
    "legal_moves starting position" => fn ->
      moves = Position.legal_moves(Position.starting_position())
      unless length(moves) == 20, do: raise("expected 20 moves")
      moves
    end,
    "legal_moves middlegame" => fn ->
      moves = Position.legal_moves(position)
      moves
    end,
    "legal_moves in check" => fn ->
      moves = Position.legal_moves(check_position)
      moves
    end
  },
  warmup: 2,
  time: 5,
  memory_time: 2,
  parallel: 1
)
