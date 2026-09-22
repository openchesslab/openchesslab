defmodule Chess.PositionDraft do
  @moduledoc """
  A temporary editable chess position.

  A draft may contain an invalid intermediate position. It can only be
  applied when its final position passes `Chess.Position.validate/1`.
  """

  alias Chess.Board
  alias Chess.Position
  alias Chess.Square

  @type t :: %__MODULE__{
          position: Position.t()
        }

  @enforce_keys [:position]
  defstruct [:position]

  @spec new(Position.t()) :: t()
  def new(%Position{} = position) do
    %__MODULE__{
      position: position
    }
  end

  @spec position(t()) :: Position.t()
  def position(%__MODULE__{position: position}), do: position

  @spec put_piece(t(), Square.t(), Board.piece()) :: t()
  def put_piece(%__MODULE__{} = draft, square, piece) do
    %{draft | position: Position.put_piece(draft.position, square, piece)}
  end

  @spec remove_piece(t(), Square.t()) :: t()
  def remove_piece(%__MODULE__{} = draft, square) do
    %{draft | position: Position.remove_piece(draft.position, square)}
  end

  @spec set_side_to_move(t(), :white | :black) :: t()
  def set_side_to_move(%__MODULE__{} = draft, side_to_move)
      when side_to_move in [:white, :black] do
    %{draft | position: %{draft.position | side_to_move: side_to_move}}
  end

  @type castling_right ::
          :white_kingside
          | :white_queenside
          | :black_kingside
          | :black_queenside

  @spec set_castling_right(t(), castling_right(), boolean()) :: t()
  def set_castling_right(%__MODULE__{} = draft, right, enabled)
      when right in [
             :white_kingside,
             :white_queenside,
             :black_kingside,
             :black_queenside
           ] and is_boolean(enabled) do
    castling_rights =
      if enabled do
        MapSet.put(draft.position.castling_rights, right)
      else
        MapSet.delete(draft.position.castling_rights, right)
      end

    %{draft | position: %{draft.position | castling_rights: castling_rights}}
  end

  @spec set_en_passant(t(), Square.t() | nil) :: t()
  def set_en_passant(%__MODULE__{} = draft, en_passant)
      when is_nil(en_passant) or en_passant in 0..63 do
    %{draft | position: %{draft.position | en_passant: en_passant}}
  end

  @spec apply(t()) :: {:ok, Position.t()} | {:error, [atom()]}
  def apply(%__MODULE__{position: position}) do
    case Position.validate(position) do
      :ok -> {:ok, position}
      {:error, reasons} -> {:error, reasons}
    end
  end
end
