defmodule Features.Feature do
  @moduledoc """
  A single catalogue feature: a stable id, the spec section and bullet it
  claims in `docs/POSITION_FEATURES.md`, and the function that computes its
  value from a board.
  """

  @type claim :: {pos_integer(), String.t()}

  @type t :: %__MODULE__{
          id: String.t(),
          section: pos_integer(),
          claims: [claim()],
          compute: (Features.Chess.Board.t() -> term())
        }

  defstruct [:id, :section, :claims, :compute]

  @spec new(String.t(), pos_integer(), [claim()], (Features.Chess.Board.t() -> term())) :: t()
  def new(id, section, claims, compute) when is_binary(id) and is_list(claims) do
    %__MODULE__{id: id, section: section, claims: claims, compute: compute}
  end
end
