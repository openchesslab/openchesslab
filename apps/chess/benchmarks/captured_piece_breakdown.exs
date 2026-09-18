alias Chess.Bitboard
alias Chess.Move
alias Chess.Position

defmodule BenchmarkHelpers do
  import Bitwise

  @piece_fields [
    {:white_pawns, :white, :pawn},
    {:white_knights, :white, :knight},
    {:white_bishops, :white, :bishop},
    {:white_rooks, :white, :rook},
    {:white_queens, :white, :queen},
    {:white_king, :white, :king},
    {:black_pawns, :black, :pawn},
    {:black_knights, :black, :knight},
    {:black_bishops, :black, :bishop},
    {:black_rooks, :black, :rook},
    {:black_queens, :black, :queen},
    {:black_king, :black, :king}
  ]

  @white_piece_fields [
    {:white_pawns, :white, :pawn},
    {:white_knights, :white, :knight},
    {:white_bishops, :white, :bishop},
    {:white_rooks, :white, :rook},
    {:white_queens, :white, :queen},
    {:white_king, :white, :king}
  ]

  @black_piece_fields [
    {:black_pawns, :black, :pawn},
    {:black_knights, :black, :knight},
    {:black_bishops, :black, :bishop},
    {:black_rooks, :black, :rook},
    {:black_queens, :black, :queen},
    {:black_king, :black, :king}
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

  # Generic lookup: inspect all 12 piece bitboards.
  def captured_piece(%{board: board, to: to}) do
    captured_piece(board, to, @piece_fields)
  end

  # The side to move is white in our benchmark positions, so the
  # captured piece must be black. This measures the cheaper
  # enemy-only lookup.
  def captured_enemy_piece(%{board: board, to: to}) do
    captured_piece(board, to, @black_piece_fields)
  end

  def remove_from(%{board: board, from: from, piece: piece}) do
    remove_piece(board, from, piece)
  end

  def remove_captured(%{board: board, to: to}) do
    remove_at(board, to)
  end

  def remove_from_remove_captured_set_to(%{
        board: board,
        from: from,
        to: to,
        piece: {color, type}
      }) do
    {:ok, captured} = captured_piece(board, to, @piece_fields)

    board
    |> remove_piece(from, {color, type})
    |> remove_piece(to, captured)
    |> set_piece(to, color, type)
  end

  def remove_from_remove_enemy_set_to(%{board: board, from: from, to: to, piece: {color, type}}) do
    {:ok, captured} = captured_enemy_piece(%{board: board, to: to})

    board
    |> remove_piece(from, {color, type})
    |> remove_piece(to, captured)
    |> set_piece(to, color, type)
  end

  def after_move(%{board: board, move: move, piece: piece}) do
    Bitboard.after_move(board, move, piece)
  end

  def print_case(name, %{from: from, to: to, piece: piece}) do
    IO.puts(
      "#{name}: #{Chess.Square.to_algebraic(from)}-#{Chess.Square.to_algebraic(to)} #{inspect(piece)}"
    )
  end

  defp captured_piece(board, square, fields) do
    mask = 1 <<< square

    Enum.reduce_while(fields, {:error, :empty}, fn {field, color, type}, _acc ->
      if (Map.fetch!(board, field) &&& mask) != 0 do
        {:halt, {:ok, {color, type}}}
      else
        {:cont, {:error, :empty}}
      end
    end)
  end

  defp remove_at(board, square) do
    mask = bnot(1 <<< square)

    Enum.reduce_while(@piece_fields, board, fn {field, _color, _type}, board ->
      if (Map.fetch!(board, field) &&& 1 <<< square) != 0 do
        {:halt, Map.update!(board, field, &band(&1, mask))}
      else
        {:cont, board}
      end
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

capture = BenchmarkHelpers.capture(position, "a4", "c6")

IO.puts("\nBenchmark case:")
BenchmarkHelpers.print_case("capture", capture)

{:ok, captured} = BenchmarkHelpers.captured_piece(capture)

IO.puts("Captured piece: #{inspect(captured)}")

Benchee.run(
  %{
    "captured piece: all 12 fields" => fn -> BenchmarkHelpers.captured_piece(capture) end,
    "captured piece: enemy 6 fields" => fn -> BenchmarkHelpers.captured_enemy_piece(capture) end,
    "remove captured: all 12 fields" => fn -> BenchmarkHelpers.remove_captured(capture) end,
    "remove from + remove captured + set to: all 12 lookup" => fn ->
      BenchmarkHelpers.remove_from_remove_captured_set_to(capture)
    end,
    "remove from + remove captured + set to: enemy lookup" => fn ->
      BenchmarkHelpers.remove_from_remove_enemy_set_to(capture)
    end,
    "after_move" => fn -> BenchmarkHelpers.after_move(capture) end
  },
  warmup: 2,
  time: 5,
  memory_time: 2,
  parallel: 1,
  print: [fast_warning: false]
)
