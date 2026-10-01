defmodule Analysis.Node do
  @moduledoc """
  A node in a chess game tree.

  Each node represents one occurrence of a position in the game tree.
  The canonical position itself is stored in PostgreSQL and is identified
  `position_id`.

  The root node has no transition. Every other node stores the transition
  that led from its parent to this node.
  """

  alias Analysis.Transition

  @type position_id :: pos_integer()

  @type nag :: 0..255

  @type t :: %__MODULE__{
          position_id: position_id(),
          transition: Transition.t() | nil,
          comment: String.t() | nil,
          nags: [nag()],
          children: [t()]
        }

  @max_nags 8

  @enforce_keys [:position_id]
  defstruct position_id: nil,
            transition: nil,
            comment: nil,
            nags: [],
            children: []

  @spec new(position_id()) :: t()
  def new(position_id) do
    %__MODULE__{
      position_id: position_id
    }
  end

  @spec new(position_id(), Transition.t()) :: t()
  def new(position_id, transition) do
    %__MODULE__{
      position_id: position_id,
      transition: transition
    }
  end

  @spec position_id(t()) :: position_id()
  def position_id(%__MODULE__{position_id: position_id}) do
    position_id
  end

  @spec transition(t()) :: Transition.t() | nil
  def transition(%__MODULE__{transition: transition}) do
    transition
  end

  @spec children(t()) :: [t()]
  def children(%__MODULE__{children: children}) do
    children
  end

  @spec nags(t()) :: [nag()]
  def nags(%__MODULE__{nags: nags}) do
    nags
  end

  @doc """
  Replace a node's NAGs. Values are PGN NAGs ($0-$255), deduplicated
  and capped; anything else is rejected.
  """
  @spec valid_nags?(term()) :: boolean()
  def valid_nags?(nags) when is_list(nags) do
    length(nags) <= @max_nags and Enum.all?(nags, &valid_nag?/1)
  end

  def valid_nags?(_nags), do: false

  @spec set_nags(t(), [nag()]) :: {:ok, t()} | {:error, :invalid_nags}
  def set_nags(%__MODULE__{} = node, nags) do
    if valid_nags?(nags) do
      {:ok, %{node | nags: Enum.uniq(nags)}}
    else
      {:error, :invalid_nags}
    end
  end

  defp valid_nag?(nag) when is_integer(nag), do: nag >= 0 and nag <= 255
  defp valid_nag?(_nag), do: false

  @spec leaf?(t()) :: boolean()
  def leaf?(%__MODULE__{children: children}) do
    children == []
  end

  @spec main_child(t()) :: t() | nil
  def main_child(%__MODULE__{children: [child | _]}) do
    child
  end

  def main_child(%__MODULE__{children: []}) do
    nil
  end

  @spec child_index(t(), Transition.t(), position_id()) ::
          non_neg_integer() | nil
  def child_index(%__MODULE__{children: children}, transition, position_id) do
    Enum.find_index(children, fn child ->
      transition(child) == transition and
        position_id(child) == position_id
    end)
  end

  @spec comment(t()) :: String.t() | nil
  def comment(%__MODULE__{comment: comment}) do
    comment
  end
end

# JSON encoding for the SPA. Children are encoded recursively
# (still as Node maps, not as opaque terms). The `transition` is
# either `nil` (root), `{:move, %Chess.Move{}}` (a played move), or
# `:edit` (a position edit). We flatten these into a small object so
# the wire format has the same shape the SPA sends back via the move
# and edit APIs: a move is `{"type":"move","from":N,"to":N,
# "promotion":...}` and an edit is `{"type":"edit"}`. The root's
# `nil` transition becomes JSON `null`.
#
# Note: this defimpl builds plain Elixir maps and lets the outer
# `Jason.Encode.map/2` recurse into them. Don't call Jason.Encode
# helpers from inside the encoder — those return `iodata`, which the
# outer pass would then re-interpret as a list.
defimpl Jason.Encoder, for: Analysis.Node do
  def encode(%Analysis.Node{} = n, opts) do
    Jason.Encode.map(
      %{
        position_id: n.position_id,
        transition: transition_for_wire(n.transition),
        comment: n.comment,
        children: n.children
      },
      opts
    )
  end

  defp transition_for_wire(nil), do: nil

  defp transition_for_wire({:move, %Chess.Move{from: from, to: to, promotion: promotion}}) do
    %{
      type: "move",
      from: from,
      to: to,
      promotion: encode_promotion(promotion)
    }
  end

  defp transition_for_wire(:edit) do
    %{type: "edit"}
  end

  defp encode_promotion(nil), do: nil

  defp encode_promotion(promotion) when is_atom(promotion), do: Atom.to_string(promotion)
end
