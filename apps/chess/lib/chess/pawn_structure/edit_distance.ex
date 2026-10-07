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

  import Bitwise

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

  Neighborhood traversal uses raw pawn-bitboard keys internally so intermediate
  candidates do not allocate complete `PawnStructure` structs.
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
    source
    |> structure_key()
    |> key_neighborhood(maximum_distance)
    |> Enum.map(&structure_from_key/1)
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

  defp key_neighborhood(source, maximum_distance) do
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
                      key_elementary_neighbors(structure),
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

  defp key_elementary_neighbors(structure) do
    key_rank_neighbors(structure) ++
      key_capture_like_neighbors(structure) ++
      key_pawn_removals(structure)
  end

  defp key_rank_neighbors(structure) do
    [
      :white,
      :black
    ]
    |> Enum.flat_map(fn color ->
      structure
      |> key_color_pawns(color)
      |> pawn_squares()
      |> Enum.flat_map(fn from ->
        forward =
          forward_step(color)

        [
          forward,
          -forward
        ]
        |> Enum.flat_map(fn step ->
          key_shift_variant(
            structure,
            color,
            from,
            from + step
          )
        end)
      end)
    end)
  end

  defp key_capture_like_neighbors(structure) do
    [
      :white,
      :black
    ]
    |> Enum.flat_map(fn color ->
      structure
      |> key_color_pawns(color)
      |> pawn_squares()
      |> Enum.flat_map(fn from ->
        color
        |> capture_like_destinations(from)
        |> Enum.flat_map(fn to ->
          key_shift_variant(
            structure,
            color,
            from,
            to
          )
        end)
      end)
    end)
  end

  defp key_pawn_removals(structure) do
    [
      :white,
      :black
    ]
    |> Enum.flat_map(fn color ->
      structure
      |> key_color_pawns(color)
      |> pawn_squares()
      |> Enum.map(fn square ->
        key_remove_pawn(
          structure,
          color,
          square
        )
      end)
    end)
  end

  defp key_shift_variant(structure, color, from, to) when to in 0..63 do
    if key_pawn_on_any_color?(
         structure,
         to
       ) do
      []
    else
      [
        key_relocate_pawn(
          structure,
          color,
          from,
          to
        )
      ]
    end
  end

  defp key_shift_variant(_structure, _color, _from, _to) do
    []
  end

  defp capture_like_destinations(color, square) do
    file =
      rem(
        square,
        8
      )

    rank =
      div(
        square,
        8
      )

    rank_step =
      forward_rank_step(color)

    [
      {
        file - 1,
        rank + rank_step
      },
      {
        file + 1,
        rank + rank_step
      },
      {
        file - 1,
        rank - rank_step
      },
      {
        file + 1,
        rank - rank_step
      }
    ]
    |> Enum.flat_map(fn
      {
        destination_file,
        destination_rank
      }
      when destination_file in 0..7 and
             destination_rank in 0..7 ->
        [
          destination_rank * 8 +
            destination_file
        ]

      _destination ->
        []
    end)
  end

  defp key_relocate_pawn({white, black}, :white, from, to) do
    {
      relocate_bit(
        white,
        from,
        to
      ),
      black
    }
  end

  defp key_relocate_pawn({white, black}, :black, from, to) do
    {
      white,
      relocate_bit(
        black,
        from,
        to
      )
    }
  end

  defp relocate_bit(pawns, from, to) do
    pawns
    |> band(
      bnot(
        bsl(
          1,
          from
        )
      )
    )
    |> bor(
      bsl(
        1,
        to
      )
    )
  end

  defp key_remove_pawn({white, black}, :white, square) do
    {
      clear_bit(
        white,
        square
      ),
      black
    }
  end

  defp key_remove_pawn({white, black}, :black, square) do
    {
      white,
      clear_bit(
        black,
        square
      )
    }
  end

  defp clear_bit(pawns, square) do
    band(
      pawns,
      bnot(
        bsl(
          1,
          square
        )
      )
    )
  end

  defp key_pawn_on_any_color?({white, black}, square) do
    white
    |> bor(black)
    |> band(
      bsl(
        1,
        square
      )
    )
    |> Kernel.!=(0)
  end

  defp key_color_pawns({white, _black}, :white) do
    white
  end

  defp key_color_pawns({_white, black}, :black) do
    black
  end

  defp pawn_squares(pawns) do
    for square <- 0..63,
        band(
          pawns,
          bsl(
            1,
            square
          )
        ) != 0 do
      square
    end
  end

  defp forward_step(:white) do
    8
  end

  defp forward_step(:black) do
    -8
  end

  defp forward_rank_step(:white) do
    1
  end

  defp forward_rank_step(:black) do
    -1
  end

  defp structure_key(%PawnStructure{white: white, black: black}) do
    {
      white,
      black
    }
  end

  defp structure_from_key({white, black}) do
    %PawnStructure{
      white: white,
      black: black
    }
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
