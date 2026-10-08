defmodule Features.Chess.FEN do
  @moduledoc """
  FEN parsing and serialization for `Features.Chess.Board`.
  """

  import Bitwise

  alias Features.Chess.{Board, Square}

  @start_fen "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

  @doc "The standard starting position FEN."
  def start_fen, do: @start_fen

  @doc """
  Parse a FEN string into a board. Clocks are optional; missing clocks
  default to `0 1`.
  """
  @spec parse(String.t()) :: Board.t()
  def parse(fen \\ @start_fen) when is_binary(fen) do
    case String.split(fen) do
      [placement, side, castling, en_passant | clocks] ->
        {halfmove, fullmove} = parse_clocks(clocks)

        Board.build(parse_placement(placement),
          side_to_move: parse_side_to_move(side),
          castling: Board.parse_castling(castling),
          en_passant: parse_en_passant(en_passant),
          halfmove_clock: halfmove,
          fullmove_number: fullmove
        )

      _ ->
        raise ArgumentError, "invalid FEN: #{inspect(fen)}"
    end
  end

  @doc "Serialize a board as a FEN string."
  @spec to_fen(Board.t()) :: String.t()
  def to_fen(board) do
    Enum.join(
      [
        placement(board),
        side_to_move(board),
        Board.castling_to_string(board.castling),
        en_passant(board.en_passant),
        Integer.to_string(board.halfmove_clock),
        Integer.to_string(board.fullmove_number)
      ],
      " "
    )
  end

  defp parse_placement(placement) do
    rows = String.split(placement, "/")

    if length(rows) != 8 do
      raise ArgumentError, "invalid FEN placement: #{inspect(placement)}"
    end

    rows
    |> Enum.with_index()
    |> Enum.flat_map(fn {row, index} -> parse_row(row, 7 - index) end)
    |> Enum.reduce(%{}, fn {piece, bit}, pieces ->
      Map.update(pieces, piece, bit, &(&1 ||| bit))
    end)
  end

  defp parse_row(row, rank) do
    {pieces, file} =
      row
      |> String.graphemes()
      |> Enum.reduce({%{}, 0}, fn token, {pieces, file} ->
        case token do
          digit when digit in ~w(1 2 3 4 5 6 7 8) ->
            {pieces, file + String.to_integer(digit)}

          _ ->
            bit = 1 <<< (rank * 8 + file)
            piece = piece_from_char(token)
            {Map.update(pieces, piece, bit, &(&1 ||| bit)), file + 1}
        end
      end)

    if file != 8 do
      raise ArgumentError, "invalid FEN row: #{inspect(row)}"
    end

    pieces
  end

  defp piece_from_char("P"), do: {:white, :pawns}
  defp piece_from_char("N"), do: {:white, :knights}
  defp piece_from_char("B"), do: {:white, :bishops}
  defp piece_from_char("R"), do: {:white, :rooks}
  defp piece_from_char("Q"), do: {:white, :queens}
  defp piece_from_char("K"), do: {:white, :kings}
  defp piece_from_char("p"), do: {:black, :pawns}
  defp piece_from_char("n"), do: {:black, :knights}
  defp piece_from_char("b"), do: {:black, :bishops}
  defp piece_from_char("r"), do: {:black, :rooks}
  defp piece_from_char("q"), do: {:black, :queens}
  defp piece_from_char("k"), do: {:black, :kings}
  defp piece_from_char(other), do: raise(ArgumentError, "invalid FEN piece: #{inspect(other)}")

  @doc "FEN character for a `{color, piece_type}` tuple, e.g. `{white, queens}` → `\"Q\"`."
  @spec piece_char({atom(), atom()}) :: String.t()
  def piece_char({:white, :pawns}), do: "P"
  def piece_char({:white, :knights}), do: "N"
  def piece_char({:white, :bishops}), do: "B"
  def piece_char({:white, :rooks}), do: "R"
  def piece_char({:white, :queens}), do: "Q"
  def piece_char({:white, :kings}), do: "K"
  def piece_char({:black, :pawns}), do: "p"
  def piece_char({:black, :knights}), do: "n"
  def piece_char({:black, :bishops}), do: "b"
  def piece_char({:black, :rooks}), do: "r"
  def piece_char({:black, :queens}), do: "q"
  def piece_char({:black, :kings}), do: "k"

  defp parse_side_to_move("w"), do: :white
  defp parse_side_to_move("b"), do: :black

  defp parse_side_to_move(other) do
    raise ArgumentError, "invalid side to move: #{inspect(other)}"
  end

  defp parse_en_passant("-"), do: nil
  defp parse_en_passant(square), do: Square.parse(square)

  defp parse_clocks([]), do: {0, 1}
  defp parse_clocks([halfmove]), do: {String.to_integer(halfmove), 1}

  defp parse_clocks([halfmove, fullmove | _]) do
    {String.to_integer(halfmove), String.to_integer(fullmove)}
  end

  defp placement(board) do
    for(rank <- 7..0//-1, do: rank_row(board, rank))
    |> Enum.join("/")
  end

  defp rank_row(board, rank) do
    {row, empty} =
      Enum.reduce(0..7, {"", 0}, fn file, {row, empty} ->
        case Board.piece_at(board, Square.new(file, rank)) do
          nil ->
            {row, empty + 1}

          piece ->
            {row <> empty_run(empty) <> piece_char(piece), 0}
        end
      end)

    row <> empty_run(empty)
  end

  defp empty_run(0), do: ""
  defp empty_run(count), do: Integer.to_string(count)

  defp side_to_move(board) do
    if board.side_to_move == :white, do: "w", else: "b"
  end

  defp en_passant(nil), do: "-"
  defp en_passant(square), do: Square.to_string(square)
end
