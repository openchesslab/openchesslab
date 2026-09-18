alias Chess.Bitboard
alias Chess.Move
alias Chess.Position
import Bitwise

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

  def move_case(position, from, to) do
    from = square(from)
    to = square(to)
    piece = Position.piece_at(position, from)

    %{
      board: Bitboard.from_position(position),
      from: from,
      to: to,
      piece: piece
    }
  end

  def remove(board, square) do
    Bitboard.remove(board, square)
  end

  # Dit is de kandidaat-implementatie die we willen benchmarken.
  #
  # Bewust hier in de benchmark gedefinieerd, zodat we nog niets
  # aan productiecode hoeven te veranderen.
  def remove_piece(
        board,
        square,
        {color, piece_type}
      ) do
    field = piece_field(color, piece_type)
    mask = Bitwise.bnot(1 <<< square)

    Map.update!(
      board,
      field,
      &Bitwise.band(&1, mask)
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

  def print_case(name, %{from: from, to: to, piece: piece}) do
    IO.puts(
      "#{name}: #{Chess.Square.to_algebraic(from)}-" <>
        "#{Chess.Square.to_algebraic(to)} #{inspect(piece)}"
    )
  end
end

starting_position = Position.starting_position()
middlegame_position = BenchmarkHelpers.middlegame_position()

starting =
  BenchmarkHelpers.move_case(
    starting_position,
    "e2",
    "e4"
  )

middlegame_non_capture =
  BenchmarkHelpers.move_case(
    middlegame_position,
    "a4",
    "b5"
  )

middlegame_capture =
  BenchmarkHelpers.move_case(
    middlegame_position,
    "a4",
    "c6"
  )

IO.puts("\nBenchmark cases:")
BenchmarkHelpers.print_case("starting", starting)
BenchmarkHelpers.print_case("middlegame non-capture", middlegame_non_capture)
BenchmarkHelpers.print_case("middlegame capture", middlegame_capture)

Benchee.run(
  %{
    "starting: remove" => fn ->
      BenchmarkHelpers.remove(
        starting.board,
        starting.from
      )
    end,
    "starting: remove_piece" => fn ->
      BenchmarkHelpers.remove_piece(
        starting.board,
        starting.from,
        starting.piece
      )
    end,
    "middlegame non-capture: remove" => fn ->
      BenchmarkHelpers.remove(
        middlegame_non_capture.board,
        middlegame_non_capture.from
      )
    end,
    "middlegame non-capture: remove_piece" => fn ->
      BenchmarkHelpers.remove_piece(
        middlegame_non_capture.board,
        middlegame_non_capture.from,
        middlegame_non_capture.piece
      )
    end,
    "middlegame capture: remove" => fn ->
      BenchmarkHelpers.remove(
        middlegame_capture.board,
        middlegame_capture.from
      )
    end,
    "middlegame capture: remove_piece" => fn ->
      BenchmarkHelpers.remove_piece(
        middlegame_capture.board,
        middlegame_capture.from,
        middlegame_capture.piece
      )
    end
  },
  warmup: 2,
  time: 5,
  memory_time: 2,
  parallel: 1,
  print: [fast_warning: false]
)
