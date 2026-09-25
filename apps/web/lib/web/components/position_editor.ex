defmodule Web.Components.PositionEditor do
  use Web, :html

  alias Chess.Square

  attr(:position, :any, required: true)
  attr(:edit_error, :string, default: nil)

  def position_editor(assigns) do
    ~H"""
    <section id="position-editor">
      <p id="side-to-move">
        {color_label(@position.side_to_move)}
      </p>

      <form id="side-to-move-form" phx-submit="set_side_to_move">
        <select name="edit[side_to_move]" required>
          <option
            value="white"
            selected={@position.side_to_move == :white}
          >
            {gettext("White")}
          </option>

          <option
            value="black"
            selected={@position.side_to_move == :black}
          >
            {gettext("Black")}
          </option>
        </select>

        <button type="submit">
          {gettext("Set side to move")}
        </button>
      </form>

      <div id="castling-rights">
        <p id="castling-white-kingside">
          {gettext("White kingside")}: {castling_status(@position, :white_kingside)}
        </p>

        <p id="castling-white-queenside">
          {gettext("White queenside")}: {castling_status(@position, :white_queenside)}
        </p>

        <p id="castling-black-kingside">
          {gettext("Black kingside")}: {castling_status(@position, :black_kingside)}
        </p>

        <p id="castling-black-queenside">
          {gettext("Black queenside")}: {castling_status(@position, :black_queenside)}
        </p>
      </div>

      <form id="castling-right-form" phx-submit="set_castling_right">
        <select name="edit[right]" required>
          <option value="white_kingside">{gettext("White kingside")}</option>

          <option value="white_queenside">{gettext("White queenside")}</option>

          <option value="black_kingside">{gettext("Black kingside")}</option>

          <option value="black_queenside">{gettext("Black queenside")}</option>
        </select>

        <select name="edit[enabled]" required>
          <option value="true">{gettext("Enabled")}</option>

          <option value="false">{gettext("Disabled")}</option>
        </select>

        <button type="submit">
          {gettext("Set castling right")}
        </button>
      </form>

      <p id="en-passant">
        {gettext("En passant")}: {en_passant_label(@position.en_passant)}
      </p>

      <form id="en-passant-form" phx-submit="set_en_passant">
        <input
          type="text"
          name="edit[en_passant]"
          placeholder={gettext("Square or none")}
          required
        />
        <button type="submit">
          {gettext("Set en passant")}
        </button>
      </form>

      <form id="remove-piece-form" phx-submit="remove_piece">
        <input
          type="text"
          name="edit[square]"
          placeholder={gettext("Square")}
          required
        />
        <button type="submit">
          {gettext("Remove piece")}
        </button>
      </form>

      <form id="put-piece-form" phx-submit="put_piece">
        <input
          type="text"
          name="edit[square]"
          placeholder={gettext("Square")}
          required
        />
        <select name="edit[color]" required>
          <option value="white">{gettext("White")}</option>

          <option value="black">{gettext("Black")}</option>
        </select>

        <select name="edit[piece]" required>
          <option value="king">{gettext("King")}</option>

          <option value="queen">{gettext("Queen")}</option>

          <option value="rook">{gettext("Rook")}</option>

          <option value="bishop">{gettext("Bishop")}</option>

          <option value="knight">{gettext("Knight")}</option>

          <option value="pawn">{gettext("Pawn")}</option>
        </select>

        <button type="submit">
          {gettext("Put piece")}
        </button>
      </form>

      <%= if @edit_error do %>
        <p id="edit-error" role="alert">{@edit_error}</p>
      <% end %>
    </section>
    """
  end

  defp color_label(:white), do: gettext("White")
  defp color_label(:black), do: gettext("Black")

  defp castling_status(position, right) do
    if MapSet.member?(position.castling_rights, right) do
      gettext("Enabled")
    else
      gettext("Disabled")
    end
  end

  defp en_passant_label(nil), do: gettext("None")
  defp en_passant_label(square), do: Square.to_algebraic(square)
end
