defmodule Chess.PawnStructureEditNeighborhoodOptimizationTest do
  use ExUnit.Case, async: true

  alias Chess.PawnStructure
  alias Chess.PawnStructure.EditDistance

  test "raw-key neighborhood preserves primitive breadth-first discovery order" do
    source =
      %PawnStructure{
        white: 0x0E817000,
        black: 0x00029D6000000000
      }

    assert EditDistance.neighborhood(
             source,
             1
           ) ==
             reference_neighborhood(
               source,
               1
             )

    assert EditDistance.neighborhood(
             source,
             2
           ) ==
             reference_neighborhood(
               source,
               2
             )
  end

  defp reference_neighborhood(source, maximum_distance) do
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
