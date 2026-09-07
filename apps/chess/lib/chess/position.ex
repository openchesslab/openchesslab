defmodule Chess.Position do
  @moduledoc """
  Represents a chess position.

  A position is defined by:

    * the pieces on the board
    * the side to move
    * the castling rights
    * the en passant target square

  Halfmove and fullmove counters are not part of position identity.
  """

  @type castling_right ::
          :white_kingside
          | :white_queenside
          | :black_kingside
          | :black_queenside

  @type t :: %__MODULE__{
          board: Chess.Board.t(),
          side_to_move: Chess.Board.color(),
          castling_rights: MapSet.t(castling_right()),
          en_passant: Chess.Square.t() | nil
        }

  @enforce_keys [:board, :side_to_move, :castling_rights, :en_passant]

  defstruct [
    :board,
    :side_to_move,
    :castling_rights,
    :en_passant
  ]

  @spec new() :: t()
  def new do
    %__MODULE__{
      board: Chess.Board.empty(),
      side_to_move: :white,
      castling_rights: MapSet.new(),
      en_passant: nil
    }
  end

  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      board: Keyword.get(opts, :board, Chess.Board.empty()),
      side_to_move: Keyword.get(opts, :side_to_move, :white),
      castling_rights: Keyword.get(opts, :castling_rights, MapSet.new()),
      en_passant: Keyword.get(opts, :en_passant)
    }
  end

  @spec starting_position() :: t()
  def starting_position do
    board =
      Chess.Board.empty()
      |> place_back_rank(:white, 0)
      |> place_pawns(:white, 8)
      |> place_back_rank(:black, 56)
      |> place_pawns(:black, 48)

    %__MODULE__{
      board: board,
      side_to_move: :white,
      castling_rights:
        MapSet.new([
          :white_kingside,
          :white_queenside,
          :black_kingside,
          :black_queenside
        ]),
      en_passant: nil
    }
  end

  @spec piece_at(t(), Chess.Square.t()) :: Chess.Board.piece() | nil
  def piece_at(%__MODULE__{board: board}, square) do
    Chess.Board.get(board, square)
  end

  @spec put_piece(t(), Chess.Square.t(), Chess.Board.piece()) :: t()
  def put_piece(%__MODULE__{board: board} = position, square, piece) do
    %{position | board: Chess.Board.put(board, square, piece)}
  end

  @spec remove_piece(t(), Chess.Square.t()) :: t()
  def remove_piece(%__MODULE__{board: board} = position, square) do
    %{position | board: Chess.Board.remove(board, square)}
  end

  @spec pieces(t()) :: [{Chess.Square.t(), Chess.Board.piece()}]
  def pieces(%__MODULE__{board: board}) do
    Chess.Board.pieces(board)
  end

  defp place_back_rank(board, color, rank_start) do
    pieces = [
      {0, :rook},
      {1, :knight},
      {2, :bishop},
      {3, :queen},
      {4, :king},
      {5, :bishop},
      {6, :knight},
      {7, :rook}
    ]

    Enum.reduce(pieces, board, fn {offset, type}, board ->
      Chess.Board.put(board, rank_start + offset, {color, type})
    end)
  end

  defp place_pawns(board, color, rank_start) do
    Enum.reduce(0..7, board, fn offset, board ->
      Chess.Board.put(board, rank_start + offset, {color, :pawn})
    end)
  end
end
