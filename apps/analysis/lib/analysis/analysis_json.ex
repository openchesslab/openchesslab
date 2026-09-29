defmodule Analysis.AnalysisJSON do
  @moduledoc """
  Builds the SPA's JSON wire form for an `Analysis.Analysis`.

  The current `Jason.Encoder for Analysis.Node` only ships the tree
  structure (`position_id`, `transition`, `comment`, `children`).
  The SPA's read-only render also needs every node's actual board
  position, so this module walks the tree, looks up each
  `position_id` via `Analysis.PositionStore`, and produces a tree
  of plain maps with a `position` field embedded alongside
  `position_id`.

  Repeated `position_id`s (transpositions) only fetch from
  `PositionStore` once per `expand/2` call. Missing positions are
  surfaced as `position: nil` rather than raising — the SPA should
  render a placeholder and keep going.

  The transition encoding matches the existing `Jason.Encoder for
  Analysis.Node` so the SPA sees the same shape whether it gets the
  full expanded tree from this module or a bare tree from the
  encoder:

      nil                                  → transition: nil
      {:move, %Chess.Move{...}}             → {type: "move", from, to, promotion}
      :edit                                → {type: "edit"}
  """

  alias Analysis.Node
  alias Analysis.PositionStore

  @spec expand(Analysis.Analysis.t(), keyword()) :: map()
  def expand(%Analysis.Analysis{} = analysis, opts \\ []) do
    position_cache = Keyword.get(opts, :position_cache, %{})
    revision = Keyword.get(opts, :revision)

    %{
      id: analysis.id,
      start: analysis.start,
      root: expand_node(Analysis.Analysis.root(analysis), nil, position_cache),
      source_game_record_id: analysis.source_game_record_id,
      metadata: analysis.metadata,
      revision: revision
    }
  end

  defp expand_node(%Node{} = node, parent_position, cache) do
    position_id = Node.position_id(node)
    {cache, position} = fetch_position(position_id, cache)

    %{
      position_id: position_id,
      transition: transition_for_wire(Node.transition(node)),
      comment: Node.comment(node),
      # Canonical SAN of the transition, as chess notation (check and
      # mate suffixes, castling, captures, disambiguation included). The
      # SPA localises the piece letters for display and keeps this form
      # for PGN. Nil for the root and for edits.
      san: san_for(parent_position, Node.transition(node)),
      nags: Node.nags(node),
      position: position,
      children: Enum.map(Node.children(node), &expand_node(&1, position, cache))
    }
  end

  defp san_for(nil, _transition), do: nil

  defp san_for(%Chess.Position{} = parent_position, transition) do
    case Analysis.TransitionNotation.format(parent_position, transition) do
      {:ok, notation} -> notation
      _ -> nil
    end
  end

  defp fetch_position(position_id, cache) do
    case Map.fetch(cache, position_id) do
      {:ok, position} ->
        {cache, position}

      :error ->
        position =
          case PositionStore.get(position_id) do
            {:ok, %Chess.Position{} = position} -> position
            _ -> nil
          end

        {Map.put(cache, position_id, position), position}
    end
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

  defp transition_for_wire(:edit), do: %{type: "edit"}

  defp encode_promotion(nil), do: nil

  defp encode_promotion(promotion) when is_atom(promotion), do: Atom.to_string(promotion)
end
