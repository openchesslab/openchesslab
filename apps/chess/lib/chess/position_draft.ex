defmodule Chess.PositionDraft do
  @moduledoc """
  A temporary editable chess position.

  A draft may contain an invalid intermediate position. It can only be
  applied when its final position passes `Chess.Position.validate/1`.

  `move_piece/4` and `place_piece/3` are the free-manipulation
  primitives ("what if the pawn was on h3?"). They apply the edit,
  normalize the position (clear en passant, prune castling rights the
  new placement invalidates) and validate the result, so callers get
  either an appliable draft or the validation reasons.
  """

  alias Chess.Board
  alias Chess.Position
  alias Chess.Square

  @type t :: %__MODULE__{
          position: Position.t()
        }

  @type promotion :: :queen | :rook | :bishop | :knight

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
  def set_side_to_move(%__MODULE__{} = draft, side_to_move) when side_to_move in [:white, :black] do
    %{draft | position: %{draft.position | side_to_move: side_to_move}}
  end

  @type castling_right ::
          :white_kingside
          | :white_queenside
          | :black_kingside
          | :black_queenside

  @spec set_castling_right(t(), castling_right(), boolean()) :: t()
  def set_castling_right(%__MODULE__{} = draft, right, enabled)
      when right in [:white_kingside, :white_queenside, :black_kingside, :black_queenside] and is_boolean(enabled) do
    castling_rights =
      if enabled do
        MapSet.put(draft.position.castling_rights, right)
      else
        MapSet.delete(draft.position.castling_rights, right)
      end

    %{draft | position: %{draft.position | castling_rights: castling_rights}}
  end

  @spec set_en_passant(t(), Square.t() | nil) :: t()
  def set_en_passant(%__MODULE__{} = draft, en_passant) when is_nil(en_passant) or en_passant in 0..63 do
    %{draft | position: %{draft.position | en_passant: en_passant}}
  end

  @spec apply(t()) :: {:ok, Position.t()} | {:error, [atom()]}
  def apply(%__MODULE__{position: position}) do
    case Position.validate(position) do
      :ok -> {:ok, position}
      {:error, reasons} -> {:error, reasons}
    end
  end

  @doc """
  Like `apply/1`, but returns the draft itself so placement pipelines
  can keep editing.
  """
  @spec validate(t()) :: {:ok, t()} | {:error, [atom()]}
  def validate(%__MODULE__{} = draft) do
    case apply(draft) do
      {:ok, _position} -> {:ok, draft}
      {:error, reasons} -> {:error, reasons}
    end
  end

  @doc """
  Moves the piece on `from` to `to`, replacing whatever sits on `to`
  (capture on an enemy piece, replace on an own one) and promoting a
  pawn when a promotion kind is given.

  The resulting position is normalized and validated: this is an
  analysis edit, not a legal move, so `from` must simply contain a
  piece and the result must be a structurally valid position.
  """
  @spec move_piece(t(), Square.t(), Square.t(), promotion() | nil) ::
          {:ok, t()} | {:error, :no_piece | [atom()]}
  def move_piece(%__MODULE__{} = draft, from, to, promotion \\ nil) do
    case Board.get(draft.position.board, from) do
      nil ->
        {:error, :no_piece}

      {color, kind} ->
        board =
          draft.position.board
          |> Board.remove(from)
          |> Board.remove(to)
          |> Board.put(to, {color, promoted_kind(kind, promotion)})

        draft
        |> with_board(board)
        |> normalize()
        |> validate()
    end
  end

  @doc """
  Puts `piece` on `square`, replacing whatever is there; `nil` removes
  the piece instead. Normalized and validated like `move_piece/4`.
  """
  @spec place_piece(t(), Square.t(), Board.piece() | nil) ::
          {:ok, t()} | {:error, [atom()]}
  def place_piece(%__MODULE__{} = draft, square, piece) do
    board =
      case piece do
        nil -> Board.remove(draft.position.board, square)
        {_color, _kind} = piece -> Board.put(draft.position.board, square, piece)
      end

    draft
    |> with_board(board)
    |> normalize()
    |> validate()
  end

  # --- Internals ------------------------------------------------------

  defp with_board(draft, board) do
    %{draft | position: %{draft.position | board: board}}
  end

  defp promoted_kind(:pawn, promotion) when promotion in [:queen, :rook, :bishop, :knight], do: promotion

  defp promoted_kind(kind, _promotion), do: kind

  # A board edit invalidates the en-passant target (it only exists
  # right after a double pawn push) and any castling right whose king
  # or rook no longer sits on its home square.
  defp normalize(draft) do
    position = %{draft.position | en_passant: nil}

    rights =
      MapSet.intersection(
        position.castling_rights,
        Position.structurally_valid_castling_rights(position)
      )

    %{draft | position: %{position | castling_rights: rights}}
  end
end
