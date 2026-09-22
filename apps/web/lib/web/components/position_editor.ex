defmodule Web.Components.PositionEditor do
  use Phoenix.Component

  alias Chess.Square

  attr(:position, :any, required: true)
  attr(:edit_error, :string, default: nil)

  def position_editor(assigns) do
    ~H"""
    <section id="position-editor">
      <p id="side-to-move">
        {if @position.side_to_move == :white, do: "White", else: "Black"}
      </p>
      
      <form id="side-to-move-form" phx-submit="set_side_to_move">
        <select name="edit[side_to_move]" required>
          <option
            value="white"
            selected={@position.side_to_move == :white}
          >
            White
          </option>
          
          <option
            value="black"
            selected={@position.side_to_move == :black}
          >
            Black
          </option>
        </select>
        
        <button type="submit">
          Set side to move
        </button>
      </form>
      
      <div id="castling-rights">
        <p id="castling-white-kingside">
          White kingside: {castling_status(@position, :white_kingside)}
        </p>
        
        <p id="castling-white-queenside">
          White queenside: {castling_status(@position, :white_queenside)}
        </p>
        
        <p id="castling-black-kingside">
          Black kingside: {castling_status(@position, :black_kingside)}
        </p>
        
        <p id="castling-black-queenside">
          Black queenside: {castling_status(@position, :black_queenside)}
        </p>
      </div>
      
      <form id="castling-right-form" phx-submit="set_castling_right">
        <select name="edit[right]" required>
          <option value="white_kingside">White kingside</option>
          
          <option value="white_queenside">White queenside</option>
          
          <option value="black_kingside">Black kingside</option>
          
          <option value="black_queenside">Black queenside</option>
        </select>
        
        <select name="edit[enabled]" required>
          <option value="true">Enabled</option>
          
          <option value="false">Disabled</option>
        </select>
        
        <button type="submit">
          Set castling right
        </button>
      </form>
      
      <p id="en-passant">
        En passant: {en_passant_label(@position.en_passant)}
      </p>
      
      <form id="en-passant-form" phx-submit="set_en_passant">
        <input
          type="text"
          name="edit[en_passant]"
          placeholder="Square or none"
          required
        />
        <button type="submit">
          Set en passant
        </button>
      </form>
      
      <form id="remove-piece-form" phx-submit="remove_piece">
        <input
          type="text"
          name="edit[square]"
          placeholder="Square"
          required
        />
        <button type="submit">
          Remove piece
        </button>
      </form>
      
      <form id="put-piece-form" phx-submit="put_piece">
        <input
          type="text"
          name="edit[square]"
          placeholder="Square"
          required
        />
        <select name="edit[color]" required>
          <option value="white">White</option>
          
          <option value="black">Black</option>
        </select>
        
        <select name="edit[piece]" required>
          <option value="king">King</option>
          
          <option value="queen">Queen</option>
          
          <option value="rook">Rook</option>
          
          <option value="bishop">Bishop</option>
          
          <option value="knight">Knight</option>
          
          <option value="pawn">Pawn</option>
        </select>
        
        <button type="submit">
          Put piece
        </button>
      </form>
      
      <%= if @edit_error do %>
        <p id="edit-error" role="alert">{@edit_error}</p>
      <% end %>
    </section>
    """
  end

  defp castling_status(position, right) do
    if MapSet.member?(position.castling_rights, right) do
      "Enabled"
    else
      "Disabled"
    end
  end

  defp en_passant_label(nil), do: "None"
  defp en_passant_label(square), do: Square.to_algebraic(square)
end
