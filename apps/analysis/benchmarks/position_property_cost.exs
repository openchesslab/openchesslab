# Usage from the OpenChessLab umbrella root:
#   mix run --no-start apps/analysis/benchmarks/position_property_cost.exs
#
# POSITION_PROPERTY_BENCH_GAMES (default 200)
# POSITION_PROPERTY_BENCH_PLIES (default 12)
# POSITION_PROPERTY_BENCH_RUNS  (default 5)
#
# This is a CPU-only diagnostic. It never touches PostgreSQL or PGN parsing.

defmodule Analysis.PositionPropertyCostBenchmark do
  @moduledoc false

  alias Chess.Bitboard
  alias Chess.Position
  alias Chess.PositionProperties

  def run do
    games = positive_env!("POSITION_PROPERTY_BENCH_GAMES", 200)
    plies = positive_env!("POSITION_PROPERTY_BENCH_PLIES", 12)
    runs = positive_env!("POSITION_PROPERTY_BENCH_RUNS", 5)

    IO.puts("Generating legal-game position samples (excluded from timings)...")

    positions = build_positions(games, plies)
    count = length(positions)

    if count == 0, do: raise("No position samples generated")

    IO.puts("""

    Position property CPU benchmark
    game lines:           #{games}
    maximum plies/line:   #{plies}
    distinct positions:   #{count}
    measured runs/stage:  #{runs}
    database:             not used

    Timings include the function call and small result aggregation.
    Fixture construction, PGN parsing, key encoding and PostgreSQL writes
    are excluded. Values are medians after one warm-up run.
    """)

    stages = [
      {"bitboard construction",
       fn p ->
         p |> Bitboard.from_position() |> Bitboard.occupied() |> rem(65_521)
       end},
      {"open files",
       fn p ->
         p |> PositionProperties.open_files() |> length()
       end},
      {"semi-open files",
       fn p ->
         files = PositionProperties.semi_open_files(p)
         length(files.white) + length(files.black)
       end},
      {"knight outposts",
       fn p ->
         outposts = PositionProperties.outposts(p)
         length(outposts.white) + length(outposts.black)
       end},
      {"king check status",
       fn p ->
         checked = PositionProperties.in_check(p)
         bool_count(checked.white) + bool_count(checked.black)
       end},
      {"material",
       fn p ->
         material = PositionProperties.material(p)
         material.white.pawn + material.black.pawn
       end},
      {"combined separate boards", &combined_score/1},
      {"combined shared bitboard", &combined_shared_bitboard_score/1}
    ]

    if !Enum.all?(positions, fn position ->
         combined_score(position) == combined_shared_bitboard_score(position)
       end) do
      raise "Shared-bitboard derivation changed the result checksum"
    end

    Enum.each(stages, fn {name, fun} ->
      profile_stage(name, fun, positions, count, runs)
    end)

    IO.puts("""

    Interpret these as relative CPU costs on these sampled positions,
    not as a measurement of the private PositionStore.encoded_properties/1
    implementation or end-to-end PGN import throughput.
    """)
  end

  defp build_positions(games, plies) do
    Enum.reduce(1..games, [], fn seed, accumulated ->
      {_last, accumulated} =
        Enum.reduce(1..plies, {Position.starting_position(), accumulated}, fn ply,
                                                                              {position, rows} ->
          case Position.legal_moves(position) do
            [] ->
              {position, rows}

            moves ->
              move = Enum.at(moves, rem(seed * 19 + ply * 7, length(moves)))

              case Position.apply_move(position, move) do
                {:ok, next_position} ->
                  {next_position, [next_position | rows]}

                {:error, reason} ->
                  raise "Generated legal move was rejected: #{inspect(reason)}"
              end
          end
        end)

      accumulated
    end)
    |> Enum.reverse()
    |> Enum.uniq()
  end

  defp combined_score(position) do
    open = PositionProperties.open_files(position)
    semi = PositionProperties.semi_open_files(position)
    outposts = PositionProperties.outposts(position)
    checked = PositionProperties.in_check(position)
    material = PositionProperties.material(position)

    length(open) +
      length(semi.white) + length(semi.black) +
      length(outposts.white) + length(outposts.black) +
      bool_count(checked.white) + bool_count(checked.black) +
      material.white.pawn + material.black.pawn +
      MapSet.size(position.castling_rights) +
      bool_count(not is_nil(position.en_passant))
  end

  defp combined_shared_bitboard_score(position) do
    board = Bitboard.from_position(position)
    open = PositionProperties.open_files(board)
    semi = PositionProperties.semi_open_files(board)
    outposts = PositionProperties.outposts(board)
    checked = PositionProperties.in_check(board)
    material = PositionProperties.material(board)

    length(open) +
      length(semi.white) + length(semi.black) +
      length(outposts.white) + length(outposts.black) +
      bool_count(checked.white) + bool_count(checked.black) +
      material.white.pawn + material.black.pawn +
      MapSet.size(position.castling_rights) +
      bool_count(not is_nil(position.en_passant))
  end

  defp bool_count(true), do: 1
  defp bool_count(false), do: 0

  defp profile_stage(name, fun, positions, count, runs) do
    {_warmup_time, expected_checksum} = time_stage(positions, fun)

    timings =
      Enum.map(1..runs, fn _ ->
        {elapsed_us, checksum} = time_stage(positions, fun)

        if checksum != expected_checksum do
          raise "Nondeterministic benchmark result for #{name}"
        end

        elapsed_us
      end)

    median_us = median(timings)
    per_position = median_us / count

    IO.puts(
      String.pad_trailing(name, 23) <>
        " median #{Float.round(median_us / 1000, 2)} ms" <>
        " | #{Float.round(per_position, 2)} us/position" <>
        " | checksum #{expected_checksum}"
    )
  end

  defp time_stage(positions, fun) do
    :erlang.garbage_collect()
    started = System.monotonic_time(:microsecond)
    checksum = Enum.reduce(positions, 0, fn position, sum -> sum + fun.(position) end)
    {System.monotonic_time(:microsecond) - started, checksum}
  end

  defp median(values) do
    sorted = Enum.sort(values)
    size = length(sorted)
    center = div(size, 2)

    if rem(size, 2) == 1 do
      Enum.at(sorted, center)
    else
      (Enum.at(sorted, center - 1) + Enum.at(sorted, center)) / 2
    end
  end

  defp positive_env!(name, default) do
    value = System.get_env(name, Integer.to_string(default))

    case Integer.parse(value) do
      {number, ""} when number > 0 -> number
      _ -> raise "#{name} must be a positive integer; got #{inspect(value)}"
    end
  end
end

Analysis.PositionPropertyCostBenchmark.run()
