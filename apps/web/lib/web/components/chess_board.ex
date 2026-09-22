defmodule Web.Components.ChessBoard do
  use Phoenix.Component

  alias Chess.Position
  alias Chess.Square

  attr(:position, :any, required: true)

  def chess_board(assigns) do
    assigns =
      assign(
        assigns,
        :squares,
        for(rank <- 7..0//-1, file <- 0..7) do
          rank * 8 + file
        end
      )

    ~H"""
    <div id="chess-board">
      <div
        :for={square <- @squares}
        id={"square-#{Square.to_algebraic(square)}"}
        data-square={Square.to_algebraic(square)}
        phx-click="square_clicked"
        phx-value-square={Square.to_algebraic(square)}
      >
        <%= if piece = Position.piece_at(@position, square) do %>
          <span id={"piece-#{Square.to_algebraic(square)}"}>
            {piece_symbol(piece)}
          </span>
        <% end %>
      </div>
    </div>
    """
  end

  defp piece_symbol({:white, :king}), do: "♔"
  defp piece_symbol({:white, :queen}), do: "♕"
  defp piece_symbol({:white, :rook}), do: "♖"
  defp piece_symbol({:white, :bishop}), do: "♗"
  defp piece_symbol({:white, :knight}), do: "♘"
  defp piece_symbol({:white, :pawn}), do: "♙"
  defp piece_symbol({:black, :king}), do: "♚"
  defp piece_symbol({:black, :queen}), do: "♛"
  defp piece_symbol({:black, :rook}), do: "♜"
  defp piece_symbol({:black, :bishop}), do: "♝"
  defp piece_symbol({:black, :knight}), do: "♞"
  defp piece_symbol({:black, :pawn}), do: "♟"
end
