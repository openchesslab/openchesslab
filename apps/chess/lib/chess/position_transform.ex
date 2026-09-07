defmodule Chess.PositionTransform do
  @moduledoc """
  Transformations that produce another chess position.
  """

  alias Chess.Position

  @spec swap_colors(Position.t()) :: Position.t()
  def swap_colors(%Position{} = position) do
    %{
      position
      | board: swap_board_colors(position.board),
        side_to_move: swap_color(position.side_to_move),
        castling_rights: swap_castling_rights(position.castling_rights)
    }
  end

  defp swap_board_colors(board) do
    board
    |> Chess.Board.pieces()
    |> Enum.reduce(Chess.Board.empty(), fn {square, piece}, board ->
      Chess.Board.put(board, square, swap_piece_color(piece))
    end)
  end

  defp swap_piece_color({:white, piece}), do: {:black, piece}
  defp swap_piece_color({:black, piece}), do: {:white, piece}

  defp swap_color(:white), do: :black
  defp swap_color(:black), do: :white

  defp swap_castling_rights(rights) do
    rights
    |> Enum.map(&swap_castling_right/1)
    |> MapSet.new()
  end

  defp swap_castling_right(:white_kingside), do: :black_kingside
  defp swap_castling_right(:white_queenside), do: :black_queenside
  defp swap_castling_right(:black_kingside), do: :white_kingside
  defp swap_castling_right(:black_queenside), do: :white_queenside
end
