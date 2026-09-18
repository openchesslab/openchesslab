
alias Chess.Bitboard
alias Chess.Move
alias Chess.Position

defmodule BenchmarkHelpers do
  use Bitwise

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

  def move(position, from, to) do
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

  def remove_from(%{board: board, from: from, piece: piece}) do
    remove_piece(board, from, piece)
  end

  def set_to(%{board: board, to: to, piece: {color, type}}) do
    set_piece(board, to, color, type)
  end

  def remove_from_set_to(%{board: board, from: from, to: to, piece: piece}) do
    {color, type} = piece

    board
    |> remove_piece(from, piece)
    |> set_piece(to, color, type)
  end

  def remove_from_remove_to_set_to(
        %{board: board, from: from, to: to, piece: {color, type}}
      ) do
    board
    |> remove_piece(from, {color, type})
    |> Bitboard.remove(to)
    |> set_piece(to, color, type)
  end

  def remove_from_remove_at_set_to(
        %{board: board, from: from, to: to, piece: {color, type}}
      ) do
    board
    |> remove_piece(from, {color, type})
    |> remove_at(to)
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

  # Removes the piece occupying `square`.
  #
  # Unlike Bitboard.remove/2, this updates only the piece bitboard
  # that actually contains the square.
  defp remove_at(board, square) do
    mask = bnot(1 <<< square)

    Enum.reduce_while(piece_fields(), board, fn {field, _color, _type}, board ->
      if (Map.fetch!(board, field) &&& (1 <<< square)) != 0 do
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

  defp piece_fields do
    [
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

starting_position = Position.starting_position()
middlegame_position = BenchmarkHelpers.middlegame_position()

starting = BenchmarkHelpers.move(starting_position, "e2", "e4")
middlegame_non_capture = BenchmarkHelpers.move(middlegame_position, "a4", "b5")
middlegame_capture = BenchmarkHelpers.move(middlegame_position, "a4", "c6")

IO.puts("\nBenchmark cases:")
BenchmarkHelpers.print_case("starting non-capture", starting)
BenchmarkHelpers.print_case("middlegame non-capture", middlegame_non_capture)
BenchmarkHelpers.print_case("middlegame capture", middlegame_capture)

Benchee.run(
  %{
    "starting: remove from + set to" =>
      fn -> BenchmarkHelpers.remove_from_set_to(starting) end,

    "starting: remove from + remove to + set to" =>
      fn -> BenchmarkHelpers.remove_from_remove_to_set_to(starting) end,

    "starting: remove from + remove_at + set to" =>
      fn -> BenchmarkHelpers.remove_from_remove_at_set_to(starting) end,

    "starting: after_move" =>
      fn -> BenchmarkHelpers.after_move(starting) end,

    "middlegame non-capture: remove from + set to" =>
      fn -> BenchmarkHelpers.remove_from_set_to(middlegame_non_capture) end,

    "middlegame non-capture: remove from + remove to + set to" =>
      fn -> BenchmarkHelpers.remove_from_remove_to_set_to(middlegame_non_capture) end,

    "middlegame non-capture: remove from + remove_at + set to" =>
      fn -> BenchmarkHelpers.remove_from_remove_at_set_to(middlegame_non_capture) end,

    "middlegame non-capture: after_move" =>
      fn -> BenchmarkHelpers.after_move(middlegame_non_capture) end,

    "middlegame capture: remove from + set to" =>
      fn -> BenchmarkHelpers.remove_from_set_to(middlegame_capture) end,

    "middlegame capture: remove from + remove to + set to" =>
      fn -> BenchmarkHelpers.remove_from_remove_to_set_to(middlegame_capture) end,

    "middlegame capture: remove from + remove_at + set to" =>
      fn -> BenchmarkHelpers.remove_from_remove_at_set_to(middlegame_capture) end,

    "middlegame capture: after_move" =>
      fn -> BenchmarkHelpers.after_move(middlegame_capture) end
  },
  warmup: 2,
  time: 5,
  memory_time: 2,
  parallel: 1,
  print: [fast_warning: false]
)
