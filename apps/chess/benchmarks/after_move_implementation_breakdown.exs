alias Chess.Bitboard
alias Chess.Move
alias Chess.Position

defmodule BenchmarkHelpers do
  import Bitwise

  @piece_fields [
    {:white, :pawn, :white_pawns},
    {:white, :knight, :white_knights},
    {:white, :bishop, :white_bishops},
    {:white, :rook, :white_rooks},
    {:white, :queen, :white_queens},
    {:white, :king, :white_king},
    {:black, :pawn, :black_pawns},
    {:black, :knight, :black_knights},
    {:black, :bishop, :black_bishops},
    {:black, :rook, :black_rooks},
    {:black, :queen, :black_queens},
    {:black, :king, :black_king}
  ]

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

  def capture(position, from, to) do
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

  #
  # Individual operations
  #

  def remove_from(%{board: board, from: from, piece: piece}) do
    remove_piece(board, from, piece)
  end

  def remove_to(%{board: board, to: to}) do
    remove(board, to)
  end

  def set_to(%{board: board, to: to, piece: {color, type}}) do
    set_piece(board, to, color, type)
  end

  #
  # Exact equivalent of the current after_move implementation,
  # but using local helpers so every individual operation can also
  # be benchmarked.
  #

  def after_move_non_capture(%{
        board: board,
        from: from,
        to: to,
        piece: {color, type}
      }) do
    board
    |> remove_piece(from, {color, type})
    |> remove(to)
    |> set_piece(to, color, type)
  end

  #
  # Same implementation, but explicitly named intermediate values.
  # This lets us see whether the pipe chain itself matters.
  #

  def after_move_explicit(%{
        board: board,
        from: from,
        to: to,
        piece: {color, type}
      }) do
    board1 = remove_piece(board, from, {color, type})
    board2 = remove(board1, to)
    set_piece(board2, to, color, type)
  end

  #
  # Same sequence using a known captured piece.
  #

  def after_move_known_capture(%{
        board: board,
        from: from,
        to: to,
        piece: {color, type},
        captured: captured
      }) do
    board
    |> remove_piece(from, {color, type})
    |> remove_piece(to, captured)
    |> set_piece(to, color, type)
  end

  #
  # Production implementation
  #

  def production_after_move(%{board: board, move: move, piece: piece}) do
    Bitboard.after_move(board, move, piece)
  end

  #
  # Local implementations
  #

  defp remove(board, square) do
    mask = bnot(1 <<< square)

    Enum.reduce(@piece_fields, board, fn {_color, _type, field}, board ->
      Map.update!(board, field, &band(&1, mask))
    end)
  end

  defp remove_piece(board, square, {color, piece_type}) do
    field = piece_field(color, piece_type)
    mask = bnot(1 <<< square)

    Map.update!(
      board,
      field,
      &band(&1, mask)
    )
  end

  defp set_piece(board, square, color, piece_type) do
    field = piece_field(color, piece_type)
    mask = 1 <<< square

    Map.update!(
      board,
      field,
      &bor(&1, mask)
    )
  end

  defp piece_field(:white, :pawn), do: :white_pawns
  defp piece_field(:white, :knight), do: :white_knights
  defp piece_field(:white, :bishop), do: :white_bishops
  defp piece_field(:white, :rook), do: :white_rooks
  defp piece_field(:white, :queen), do: :white_queens
  defp piece_field(:white, :king), do: :white_king

  defp piece_field(:black, :pawn), do: :black_pawns
  defp piece_field(:black, :knight), do: :black_knights
  defp piece_field(:black, :bishop), do: :black_bishops
  defp piece_field(:black, :rook), do: :black_rooks
  defp piece_field(:black, :queen), do: :black_queens
  defp piece_field(:black, :king), do: :black_king

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
end

position = BenchmarkHelpers.middlegame_position()

non_capture =
  BenchmarkHelpers.capture(position, "a4", "b5")

capture =
  BenchmarkHelpers.capture(position, "a4", "c6")

capture = Map.put(capture, :captured, {:black, :knight})

IO.puts("\nBenchmark cases:")
IO.puts("  non-capture: a4-b5 #{inspect(non_capture.piece)}")
IO.puts("  capture:     a4-c6 #{inspect(capture.piece)}")
IO.puts("  captured:    #{inspect(capture.captured)}")

Benchee.run(
  %{
    "non-capture: remove from" => fn -> BenchmarkHelpers.remove_from(non_capture) end,
    "non-capture: remove to" => fn -> BenchmarkHelpers.remove_to(non_capture) end,
    "non-capture: set to" => fn -> BenchmarkHelpers.set_to(non_capture) end,
    "non-capture: remove from + set to" => fn ->
      board = BenchmarkHelpers.remove_from(non_capture)
      BenchmarkHelpers.set_to(%{non_capture | board: board})
    end,
    "non-capture: exact implementation" => fn ->
      BenchmarkHelpers.after_move_non_capture(non_capture)
    end,
    "non-capture: explicit implementation" => fn ->
      BenchmarkHelpers.after_move_explicit(non_capture)
    end,
    "non-capture: production after_move" => fn ->
      BenchmarkHelpers.production_after_move(non_capture)
    end,
    "capture: remove from + remove to + set to" => fn ->
      BenchmarkHelpers.after_move_non_capture(capture)
    end,
    "capture: remove from + known captured + set to" => fn ->
      BenchmarkHelpers.after_move_known_capture(capture)
    end,
    "capture: explicit implementation" => fn -> BenchmarkHelpers.after_move_explicit(capture) end,
    "capture: production after_move" => fn -> BenchmarkHelpers.production_after_move(capture) end
  },
  warmup: 2,
  time: 5,
  memory_time: 2,
  parallel: 1,
  print: [fast_warning: false]
)
