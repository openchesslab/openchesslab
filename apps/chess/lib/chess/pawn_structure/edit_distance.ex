defmodule Chess.PawnStructure.EditDistance do
  @moduledoc """
  Measures and enumerates bounded directional edit distance between pawn
  structures.

  The supported elementary edits are the structural transformations exposed
  by `Chess.PawnStructure`:

    * one single-rank displacement in either direction
    * one capture-like displacement in either direction
    * removal of exactly one pawn

  Pawn removal is directional. A difference classified as a pawn addition
  describes the reverse occupancy difference, but is not itself an elementary
  transformation.

  The current bounded implementation intentionally supports distances zero,
  one and two. This is sufficient for near-neighbor search without constructing
  arbitrarily large transformation neighborhoods.
  """

  alias Chess.PawnStructure
  alias Chess.PawnStructure.Difference

  @type maximum_distance :: 0 | 1 | 2
  @type distance :: 0 | 1 | 2

  @type result ::
          {:ok, distance()}
          | :beyond_limit

  @doc """
  Returns every pawn structure reachable from the source within the requested
  maximum number of elementary edits.

  The source itself is always the first result.

  Each structure is returned exactly once. Results are ordered by discovery
  distance and then by the deterministic order of the elementary structural
  transformations.

  Because pawn removal is directional, the neighborhood is directional too:
  removing a pawn is an elementary edit, adding it again is not.
  """
  @spec neighborhood(
          PawnStructure.t(),
          maximum_distance()
        ) ::
          [PawnStructure.t()]
  def neighborhood(%PawnStructure{} = source, 0) do
    [
      source
    ]
  end

  def neighborhood(%PawnStructure{} = source, maximum_distance) when maximum_distance in 1..2 do
    {
      _seen,
      _frontier,
      result_reversed
    } =
      Enum.reduce(
        1..maximum_distance,
        {
          MapSet.new([
            source
          ]),
          [
            source
          ],
          [
            source
          ]
        },
        fn
          _distance,
          {
            seen,
            frontier,
            result_reversed
          } ->
            {
              seen,
              next_frontier_reversed,
              result_reversed
            } =
              Enum.reduce(
                frontier,
                {
                  seen,
                  [],
                  result_reversed
                },
                fn
                  structure,
                  {
                    seen,
                    next_frontier_reversed,
                    result_reversed
                  } ->
                    Enum.reduce(
                      elementary_neighbors(structure),
                      {
                        seen,
                        next_frontier_reversed,
                        result_reversed
                      },
                      fn
                        neighbor,
                        {
                          seen,
                          next_frontier_reversed,
                          result_reversed
                        } ->
                          if MapSet.member?(
                               seen,
                               neighbor
                             ) do
                            {
                              seen,
                              next_frontier_reversed,
                              result_reversed
                            }
                          else
                            {
                              MapSet.put(
                                seen,
                                neighbor
                              ),
                              [
                                neighbor
                                | next_frontier_reversed
                              ],
                              [
                                neighbor
                                | result_reversed
                              ]
                            }
                          end
                      end
                    )
                end
              )

            {
              seen,
              Enum.reverse(next_frontier_reversed),
              result_reversed
            }
        end
      )

    Enum.reverse(result_reversed)
  end

  @spec bounded(
          PawnStructure.t(),
          PawnStructure.t(),
          maximum_distance()
        ) ::
          result()
  def bounded(%PawnStructure{} = source, %PawnStructure{} = target, 0) do
    if source == target do
      {:ok, 0}
    else
      :beyond_limit
    end
  end

  def bounded(%PawnStructure{} = source, %PawnStructure{} = target, 1) do
    cond do
      source == target ->
        {:ok, 0}

      single_edit_reachable?(
        source,
        target
      ) ->
        {:ok, 1}

      true ->
        :beyond_limit
    end
  end

  def bounded(%PawnStructure{} = source, %PawnStructure{} = target, 2) do
    cond do
      source == target ->
        {:ok, 0}

      single_edit_reachable?(
        source,
        target
      ) ->
        {:ok, 1}

      two_edits_reachable?(
        source,
        target
      ) ->
        {:ok, 2}

      true ->
        :beyond_limit
    end
  end

  @spec within?(
          PawnStructure.t(),
          PawnStructure.t(),
          maximum_distance()
        ) ::
          boolean()
  def within?(%PawnStructure{} = source, %PawnStructure{} = target, maximum_distance)
      when maximum_distance in 0..2 do
    case bounded(
           source,
           target,
           maximum_distance
         ) do
      {:ok, _distance} ->
        true

      :beyond_limit ->
        false
    end
  end

  defp two_edits_reachable?(source, target) do
    source
    |> elementary_neighbors()
    |> Enum.any?(fn neighbor ->
      single_edit_reachable?(
        neighbor,
        target
      )
    end)
  end

  defp single_edit_reachable?(source, target) do
    source
    |> PawnStructure.difference(target)
    |> Difference.classify()
    |> classification_reachable?(
      source,
      target
    )
  end

  defp classification_reachable?(:exact, _source, _target) do
    true
  end

  defp classification_reachable?({:single_rank_displacement, color, from, to}, source, target) do
    relocation_reaches?(
      source,
      target,
      color,
      from,
      to
    )
  end

  defp classification_reachable?(
         {:single_capture_like_displacement, color, from, to},
         source,
         target
       ) do
    relocation_reaches?(
      source,
      target,
      color,
      from,
      to
    )
  end

  defp classification_reachable?({:single_pawn_removal, _color, _square}, source, target) do
    source
    |> PawnStructure.single_pawn_removals()
    |> Enum.member?(target)
  end

  defp classification_reachable?({:single_pawn_addition, _color, _square}, _source, _target) do
    false
  end

  defp classification_reachable?(:not_single_edit, _source, _target) do
    false
  end

  defp relocation_reaches?(source, target, color, from, to) do
    case PawnStructure.shift_pawn(
           source,
           color,
           from,
           to
         ) do
      {:ok, ^target} ->
        true

      {:ok, _other} ->
        false

      {:error, _reason} ->
        false
    end
  end

  defp elementary_neighbors(%PawnStructure{} = structure) do
    [
      PawnStructure.single_rank_neighbors(structure),
      PawnStructure.single_capture_like_neighbors(structure),
      PawnStructure.single_pawn_removals(structure)
    ]
    |> List.flatten()
    |> Enum.uniq()
  end
end
