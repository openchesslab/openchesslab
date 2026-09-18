alias Chess.Bitboard
alias Chess.Move
alias Chess.Square

import Bitwise

defmodule BenchmarkHelpers do
  import Bitwise

  def captured_enemy_piece(board, to, color) do
    enemy_fields =
      case color do
        :white ->
          [
            :black_pawns,
            :black_knights,
            :black_bishops,
            :black_rooks,
            :black_queens,
            :black_king
          ]

        :black ->
          [
            :white_pawns,
            :white_knights,
            :white_bishops,
            :white_rooks,
            :white_queens,
            :white_king
          ]
      end

    mask = 1 <<< to

    Enum.find_value(enemy_fields, fn field ->
      if band(Map.fetch!(board, field), mask) != 0 do
        {:ok, piece_type(field)}
      end
    end)
  end

  def piece_type(:white_pawns), do: :pawn
  def piece_type(:white_knights), do: :knight
  def piece_type(:white_bishops), do: :bishop
  def piece_type(:white_rooks), do: :rook
  def piece_type(:white_queens), do: :queen
  def piece_type(:white_king), do: :king

  def piece_type(:black_pawns), do: :pawn
  def piece_type(:black_knights), do: :knight
  def piece_type(:black_bishops), do: :bishop
  def piece_type(:black_rooks), do: :rook
  def piece_type(:black_queens), do: :queen
  def piece_type(:black_king), do: :king

  def remove_piece(board, square, {color, piece_type}) do
    field =
      case color do
        :white -> :"white_#{piece_type}s"
        :black -> :"black_#{piece_type}s"
      end

    mask = bnot(1 <<< square)

    Map.update!(
      board,
      field,
      &band(&1, mask)
    )
  end

  def set_piece(board, square, color, piece_type) do
    field =
      case color do
        :white -> :"white_#{piece_type}s"
        :black -> :"black_#{piece_type}s"
      end

    mask = 1 <<< square

    Map.update!(
      board,
      field,
      &bor(&1, mask)
    )
  end

  def optimized_after_move(board, move, moving_piece) do
    {color, piece_type} = moving_piece

    case captured_enemy_piece(board, move.to, color) do
      nil ->
        board
        |> remove_piece(move.from, moving_piece)
        |> set_piece(move.to, color, piece_type)

      {:ok, captured_piece_type} ->
        board
        |> remove_piece(move.from, moving_piece)
        |> remove_piece(move.to, {opposite_color(color), captured_piece_type})
        |> set_piece(move.to, color, piece_type)
    end
  end

  def optimized_non_capture(board, move, moving_piece) do
    {color, piece_type} = moving_piece

    board
    |> remove_piece(move.from, moving_piece)
    |> set_piece(move.to, color, piece_type)
  end

  def optimized_capture(board, move, moving_piece, captured_piece) do
    {color, piece_type} = moving_piece

    board
    |> remove_piece(move.from, moving_piece)
    |> remove_piece(move.to, captured_piece)
    |> set_piece(move.to, color, piece_type)
  end

  defp opposite_color(:white), do: :black
  defp opposite_color(:black), do: :white
end

# Build the middlegame position directly as a bitboard.
#
# Position after:
#
#   1. e4 e5
#   2. Nf3 Nc6
#   3. Bb5 a6
#   4. Ba4 Nf6
#   5. O-O Be7
#
# Relevant pieces:
#   White bishop: a4
#   Black knight: c6
#   b5 is empty
#
# This is all we need for the after_move benchmark.

board =
  %{
    white_pawns: 0,
    white_knights: 0,
    white_bishops: 0,
    white_rooks: 0,
    white_queens: 0,
    white_king: 0,
    black_pawns: 0,
    black_knights: 0,
    black_bishops: 0,
    black_rooks: 0,
    black_queens: 0,
    black_king: 0
  }
  |> BenchmarkHelpers.set_piece(
    Square.from_algebraic("a4"),
    :white,
    :bishop
  )
  |> BenchmarkHelpers.set_piece(
    Square.from_algebraic("c6"),
    :black,
    :knight
  )

non_capture =
  Move.new(
    Square.from_algebraic("a4"),
    Square.from_algebraic("b5")
  )

capture =
  Move.new(
    Square.from_algebraic("a4"),
    Square.from_algebraic("c6")
  )

moving_piece = {:white, :bishop}

unless BenchmarkHelpers.captured_enemy_piece(board, non_capture.to, :white) == nil do
  raise "Expected a non-capture on b5"
end

unless BenchmarkHelpers.captured_enemy_piece(board, capture.to, :white) == {:ok, :knight} do
  raise "Expected a black knight on c6"
end

Benchee.run(
  %{
    "non-capture: current after_move" => fn ->
      Bitboard.after_move(board, non_capture, moving_piece)
    end,
    "non-capture: enemy lookup" => fn ->
      BenchmarkHelpers.captured_enemy_piece(
        board,
        non_capture.to,
        :white
      )
    end,
    "non-capture: optimized path" => fn ->
      BenchmarkHelpers.optimized_non_capture(
        board,
        non_capture,
        moving_piece
      )
    end,
    "non-capture: optimized branch" => fn ->
      BenchmarkHelpers.optimized_after_move(
        board,
        non_capture,
        moving_piece
      )
    end,
    "capture: current after_move" => fn ->
      Bitboard.after_move(board, capture, moving_piece)
    end,
    "capture: enemy lookup" => fn ->
      BenchmarkHelpers.captured_enemy_piece(
        board,
        capture.to,
        :white
      )
    end,
    "capture: optimized path" => fn ->
      BenchmarkHelpers.optimized_capture(
        board,
        capture,
        moving_piece,
        {:black, :knight}
      )
    end,
    "capture: optimized branch" => fn ->
      BenchmarkHelpers.optimized_after_move(
        board,
        capture,
        moving_piece
      )
    end
  },
  warmup: 2,
  time: 5,
  memory_time: 2,
  parallel: 1,
  formatters: [
    Benchee.Formatters.Console
  ]
)
