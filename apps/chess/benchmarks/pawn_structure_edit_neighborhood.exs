import Bitwise

alias Chess.PawnStructure
alias Chess.PawnStructure.EditDistance

defmodule Chess.PawnStructureEditNeighborhoodBenchmark do
  @moduledoc false

  import Bitwise

  @source %PawnStructure{
    white: 0x0E817000,
    black: 0x00029D6000000000
  }

  @expected_distance_one 93
  @expected_distance_two 4_022

  def run do
    production_distance_one =
      EditDistance.neighborhood(
        @source,
        1
      )

    production_distance_two =
      EditDistance.neighborhood(
        @source,
        2
      )

    source_key =
      key(@source)

    raw_distance_one =
      raw_neighborhood(
        source_key,
        1
      )

    raw_distance_two =
      raw_neighborhood(
        source_key,
        2
      )

    assert_count!(
      "production distance <= 1",
      production_distance_one,
      @expected_distance_one
    )

    assert_count!(
      "production distance <= 2",
      production_distance_two,
      @expected_distance_two
    )

    assert_count!(
      "raw-key distance <= 1",
      raw_distance_one,
      @expected_distance_one
    )

    assert_count!(
      "raw-key distance <= 2",
      raw_distance_two,
      @expected_distance_two
    )

    production_distance_one_keys =
      Enum.map(
        production_distance_one,
        &key/1
      )

    production_distance_two_keys =
      Enum.map(
        production_distance_two,
        &key/1
      )

    assert_same!(
      "distance <= 1",
      production_distance_one_keys,
      raw_distance_one
    )

    assert_same!(
      "distance <= 2",
      production_distance_two_keys,
      raw_distance_two
    )

    IO.puts("""
    Pawn edit-neighborhood construction benchmark

    source pawns:          16
    distance <= 1 keys:    #{@expected_distance_one}
    distance <= 2 keys:    #{@expected_distance_two}

    The raw-key prototype preserves the exact production discovery order.
    It uses {white_bitboard, black_bitboard} tuples internally instead of
    constructing PawnStructure structs for every intermediate neighbor.
    """)

    Benchee.run(
      %{
        "production structs: distance 1" => fn ->
          EditDistance.neighborhood(
            @source,
            1
          )
        end,
        "raw keys: distance 1" => fn ->
          raw_neighborhood(
            source_key,
            1
          )
        end,
        "production structs: distance 2" => fn ->
          EditDistance.neighborhood(
            @source,
            2
          )
        end,
        "raw keys: distance 2" => fn ->
          raw_neighborhood(
            source_key,
            2
          )
        end
      },
      warmup: 1,
      time: 5,
      memory_time: 2,
      parallel: 1,
      print: [
        fast_warning: false
      ]
    )
  end

  defp raw_neighborhood(source, 0) do
    [
      source
    ]
  end

  defp raw_neighborhood(source, maximum_distance) when maximum_distance in 1..2 do
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

  defp elementary_neighbors(structure) do
    rank_neighbors(structure) ++
      capture_like_neighbors(structure) ++
      pawn_removals(structure)
  end

  defp rank_neighbors(structure) do
    [
      :white,
      :black
    ]
    |> Enum.flat_map(fn color ->
      structure
      |> color_pawns(color)
      |> pawn_squares()
      |> Enum.flat_map(fn from ->
        forward =
          forward_step(color)

        [
          forward,
          -forward
        ]
        |> Enum.flat_map(fn step ->
          shift_variant(
            structure,
            color,
            from,
            from + step
          )
        end)
      end)
    end)
  end

  defp capture_like_neighbors(structure) do
    [
      :white,
      :black
    ]
    |> Enum.flat_map(fn color ->
      structure
      |> color_pawns(color)
      |> pawn_squares()
      |> Enum.flat_map(fn from ->
        color
        |> capture_like_destinations(from)
        |> Enum.flat_map(fn to ->
          shift_variant(
            structure,
            color,
            from,
            to
          )
        end)
      end)
    end)
  end

  defp pawn_removals(structure) do
    [
      :white,
      :black
    ]
    |> Enum.flat_map(fn color ->
      structure
      |> color_pawns(color)
      |> pawn_squares()
      |> Enum.map(fn square ->
        remove_pawn(
          structure,
          color,
          square
        )
      end)
    end)
  end

  defp shift_variant(structure, color, from, to) when to in 0..63 do
    if pawn_on_any_color?(
         structure,
         to
       ) do
      []
    else
      [
        relocate_pawn(
          structure,
          color,
          from,
          to
        )
      ]
    end
  end

  defp shift_variant(_structure, _color, _from, _to) do
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

  defp relocate_pawn({white, black}, :white, from, to) do
    {
      relocate_bit(
        white,
        from,
        to
      ),
      black
    }
  end

  defp relocate_pawn({white, black}, :black, from, to) do
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

  defp remove_pawn({white, black}, :white, square) do
    {
      clear_bit(
        white,
        square
      ),
      black
    }
  end

  defp remove_pawn({white, black}, :black, square) do
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

  defp pawn_on_any_color?({white, black}, square) do
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

  defp color_pawns({white, _black}, :white) do
    white
  end

  defp color_pawns({_white, black}, :black) do
    black
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

  defp key(%PawnStructure{white: white, black: black}) do
    {
      white,
      black
    }
  end

  defp assert_count!(label, values, expected) do
    actual =
      length(values)

    if actual != expected do
      raise """
      #{label}: expected #{expected} structures, got #{actual}
      """
    end
  end

  defp assert_same!(label, production, prototype) do
    if production != prototype do
      raise """
      #{label}: raw-key prototype does not preserve the production neighborhood
      """
    end
  end
end

Chess.PawnStructureEditNeighborhoodBenchmark.run()
