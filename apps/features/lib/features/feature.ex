defmodule Features.Feature do
  @moduledoc """
  A single catalogue feature: a stable id, the spec section and bullet it
  claims in `docs/POSITION_FEATURES.md`, and the function that computes its
  value from a board.

  `board` is an optional UI hint naming the piece type (`:rook`, `:bishop`,
  ...) — or a list of types — the feature is about, for features whose value
  holds no squares of its own (counts, booleans, imbalances). The UI draws
  those pieces straight from the position whenever the value affirms a side;
  the value stays the signal, the position supplies the locations.

  Structural hints go further: `:wing_pawns` / `:wing_pieces` split the
  side's pawns or pieces by wing (queenside a–d in the side's colour,
  kingside e–h in amber), `:pawn_islands` draws the largest pawn island
  in the side's colour with the fragments amber, `:center_pieces` /
  `:center_pawns` draw the side's pieces or pawns inside the 16-square
  centre, and `:f2_f7_target` marks the f7 or f2 square the side attacks.
  """

  @type claim :: {pos_integer(), String.t()}
  @type board_hint ::
          :rook
          | :bishop
          | :knight
          | :queen
          | :pawn
          | :wing_pawns
          | :wing_pieces
          | :pawn_islands
          | :center_pieces
          | :center_pawns
          | :f2_f7_target
          | [atom()]

  @type t :: %__MODULE__{
          id: String.t(),
          section: pos_integer(),
          claims: [claim()],
          compute: (Features.Chess.Board.t() -> term()),
          board: board_hint() | nil
        }

  defstruct [:id, :section, :claims, :compute, :board]

  @spec new(
          String.t(),
          pos_integer(),
          [claim()],
          (Features.Chess.Board.t() -> term()),
          keyword()
        ) :: t()
  def new(id, section, claims, compute, opts \\ []) when is_binary(id) and is_list(claims) do
    %__MODULE__{
      id: id,
      section: section,
      claims: claims,
      compute: compute,
      board: Keyword.get(opts, :board)
    }
  end
end
