alias Chess.Bitboard
alias Chess.Move
alias Chess.Position

defmodule BenchmarkHelpers do
  def square(algebraic), do: Chess.Square.from_algebraic(algebraic)

  def middlegame_position do
    Position.starting_position()
    |> apply_moves([
      {"e2", "e4"},
      {"e7", "e5"},
      {"g1", "f3"},
      {"b8", "c6"},
      {"f1", "b5"},
      {"a7", "a6"},
      {"b5", "a4"},
      {"g8", "f6"},
      {"e1", "g1"},
      {"f8", "e7"}
    ])
  end

  def non_capture_move(position, from, to) do
    from = square(from)
    to = square(to)
    piece = Position.piece_at(position, from)
    move = Move.new(from, to)

    %{
      board: Bitboard.from_position(position),
      from: from,
      to: to,
      piece: piece,
      move: move
    }
  end

  def capture_move(position, from, to) do
    from = square(from)
    to = square(to)
    piece = Position.piece_at(position, from)
    move = Move.new(from, to)

    %{
      board: Bitboard.from_position(position),
      from: from,
      to: to,
      piece: piece,
      move: move
    }
  end

  defp apply_moves(position, moves) do
    Enum.reduce(moves, position, fn {from, to}, position ->
      {:ok, position} =
        Position.apply_move(
          position,
          Move.new(square(from), square(to))
        )

      position
    end)
  end

  def remove_from(%{board: board, from: from}) do
    Bitboard.remove(board, from)
  end

  def remove_to(%{board: board, to: to}) do
    Bitboard.remove(board, to)
  end

  def remove_both(%{board: board, from: from, to: to}) do
    board
    |> Bitboard.remove(from)
    |> Bitboard.remove(to)
  end

  def put_to(%{board: board, to: to, piece: {color, type}}) do
    Bitboard.put(board, to, {color, type})
  end

  def remove_from_then_put(%{board: board, from: from, to: to, piece: {color, type}}) do
    board
    |> Bitboard.remove(from)
    |> Bitboard.put(to, {color, type})
  end

  def after_move(%{board: board, move: move, piece: piece}) do
    Bitboard.after_move(board, move, piece)
  end

  def print_case(name, %{from: from, to: to, piece: piece}) do
    IO.puts(
      "#{name}: #{Chess.Square.to_algebraic(from)}-#{Chess.Square.to_algebraic(to)} #{inspect(piece)}"
    )
  end
end

starting_position = Position.starting_position()
middlegame_position = BenchmarkHelpers.middlegame_position()

starting =
  BenchmarkHelpers.non_capture_move(
    starting_position,
    "e2",
    "e4"
  )

middlegame_non_capture =
  BenchmarkHelpers.non_capture_move(
    middlegame_position,
    "a4",
    "b5"
  )

middlegame_capture =
  BenchmarkHelpers.capture_move(
    middlegame_position,
    "a4",
    "c6"
  )

IO.puts("\nBenchmark cases:")
BenchmarkHelpers.print_case("starting non-capture", starting)
BenchmarkHelpers.print_case("middlegame non-capture", middlegame_non_capture)
BenchmarkHelpers.print_case("middlegame capture", middlegame_capture)

Benchee.run(
  %{
    "starting: remove from" => fn ->
      BenchmarkHelpers.remove_from(starting)
    end,
    "starting: remove to" => fn ->
      BenchmarkHelpers.remove_to(starting)
    end,
    "starting: remove from + to" => fn ->
      BenchmarkHelpers.remove_both(starting)
    end,
    "starting: put to" => fn ->
      BenchmarkHelpers.put_to(starting)
    end,
    "starting: remove from + put to" => fn ->
      BenchmarkHelpers.remove_from_then_put(starting)
    end,
    "starting: after_move" => fn ->
      BenchmarkHelpers.after_move(starting)
    end,
    "middlegame non-capture: remove from" => fn ->
      BenchmarkHelpers.remove_from(middlegame_non_capture)
    end,
    "middlegame non-capture: remove to" => fn ->
      BenchmarkHelpers.remove_to(middlegame_non_capture)
    end,
    "middlegame non-capture: remove from + to" => fn ->
      BenchmarkHelpers.remove_both(middlegame_non_capture)
    end,
    "middlegame non-capture: put to" => fn ->
      BenchmarkHelpers.put_to(middlegame_non_capture)
    end,
    "middlegame non-capture: remove from + put to" => fn ->
      BenchmarkHelpers.remove_from_then_put(middlegame_non_capture)
    end,
    "middlegame non-capture: after_move" => fn ->
      BenchmarkHelpers.after_move(middlegame_non_capture)
    end,
    "middlegame capture: remove from" => fn ->
      BenchmarkHelpers.remove_from(middlegame_capture)
    end,
    "middlegame capture: remove to" => fn ->
      BenchmarkHelpers.remove_to(middlegame_capture)
    end,
    "middlegame capture: remove from + to" => fn ->
      BenchmarkHelpers.remove_both(middlegame_capture)
    end,
    "middlegame capture: put to" => fn ->
      BenchmarkHelpers.put_to(middlegame_capture)
    end,
    "middlegame capture: remove from + put to" => fn ->
      BenchmarkHelpers.remove_from_then_put(middlegame_capture)
    end,
    "middlegame capture: after_move" => fn ->
      BenchmarkHelpers.after_move(middlegame_capture)
    end
  },
  warmup: 2,
  time: 5,
  memory_time: 2,
  parallel: 1,
  print: [fast_warning: false]
)
