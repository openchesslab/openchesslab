# Compare current step-by-step sliding attack detection with a precomputed-ray
# candidate, without modifying production code or starting PostgreSQL.
# Run from the OpenChessLab repository root:
#   mix run --no-start apps/analysis/benchmarks/sliding_ray_comparison.exs

Code.require_file(Path.join(__DIR__, "pgn_long_game_fixture.exs"))

defmodule Analysis.SlidingRayComparison do
  @moduledoc false

  alias Chess.Bitboard

  defmodule Candidate do
    @moduledoc false
    import Bitwise

    alias Chess.Bitboard

    @rook_steps [8, -8, 1, -1]
    @bishop_steps [9, 7, -7, -9]

    # Directional masks are generated once at compile time. A mask excludes
    # the origin and includes every square up to the board edge.
    @ray_masks (for {step, df, dr} <- [
                      {8, 0, 1},
                      {-8, 0, -1},
                      {1, 1, 0},
                      {-1, -1, 0},
                      {9, 1, 1},
                      {7, -1, 1},
                      {-7, 1, -1},
                      {-9, -1, -1}
                    ],
                    into: %{} do
                  masks =
                    for square <- 0..63 do
                      file = rem(square, 8)
                      rank = div(square, 8)

                      Enum.reduce(1..7, 0, fn distance, acc ->
                        next_file = file + df * distance
                        next_rank = rank + dr * distance

                        if next_file in 0..7 and next_rank in 0..7 do
                          acc ||| 1 <<< (next_rank * 8 + next_file)
                        else
                          acc
                        end
                      end)
                    end

                  {step, List.to_tuple(masks)}
                end)

    @spec attacked?(Bitboard.t(), :white | :black, 0..63) :: boolean()
    def attacked?(board, :white, square) when square in 0..63 do
      attacked_with_masks(
        board,
        square,
        :black,
        board.white_pawns,
        board.white_knights,
        board.white_king,
        board.white_rooks ||| board.white_queens,
        board.white_bishops ||| board.white_queens
      )
    end

    def attacked?(board, :black, square) when square in 0..63 do
      attacked_with_masks(
        board,
        square,
        :white,
        board.black_pawns,
        board.black_knights,
        board.black_king,
        board.black_rooks ||| board.black_queens,
        board.black_bishops ||| board.black_queens
      )
    end

    defp attacked_with_masks(board, square, pawn_direction, pawns, knights, king, rooks, bishops) do
      (Bitboard.pawn_attacks(pawn_direction, square) &&& pawns) != 0 or
        (Bitboard.knight_attacks(square) &&& knights) != 0 or
        (Bitboard.king_attacks(square) &&& king) != 0 or
        ray_attacked?(Bitboard.occupied(board), square, @rook_steps, rooks) or
        ray_attacked?(Bitboard.occupied(board), square, @bishop_steps, bishops)
    end

    defp ray_attacked?(_occupied, _square, _steps, 0), do: false

    defp ray_attacked?(occupied, square, steps, attackers) do
      Enum.any?(steps, fn step ->
        ray = elem(Map.fetch!(@ray_masks, step), square)
        blockers = occupied &&& ray

        nearest =
          if step > 0 do
            blockers &&& -blockers
          else
            highest_bit(blockers)
          end

        (nearest &&& attackers) != 0
      end)
    end

    # Saturate all bits below the most significant bit, then isolate that bit.
    # Also returns zero for a zero input. Operates on unsigned 64-bit masks.
    defp highest_bit(bits) do
      bits = bits ||| bits >>> 1
      bits = bits ||| bits >>> 2
      bits = bits ||| bits >>> 4
      bits = bits ||| bits >>> 8
      bits = bits ||| bits >>> 16
      bits = bits ||| bits >>> 32
      bits - (bits >>> 1)
    end
  end

  def check!(board, color, square) do
    old = Bitboard.attacked?(board, color, square)
    new = Candidate.attacked?(board, color, square)

    if old != new do
      raise "Sliding attack mismatch for #{inspect(color)} at #{square}: " <>
              "current=#{inspect(old)} candidate=#{inspect(new)} board=#{inspect(board)}"
    end
  end

  def validate!(boards) do
    Enum.each(boards, fn board ->
      for color <- [:white, :black], square <- 0..63 do
        check!(board, color, square)
      end
    end)

    # Explicitly exercise all eight directions, all squares, both colors,
    # unobstructed attacks and a blocker between the target and the slider.
    directions = [
      {0, 1, :rook},
      {0, -1, :rook},
      {1, 0, :rook},
      {-1, 0, :rook},
      {1, 1, :bishop},
      {-1, 1, :bishop},
      {1, -1, :bishop},
      {-1, -1, :bishop}
    ]

    for square <- 0..63,
        {df, dr, type} <- directions,
        distance <- 1..7 do
      file = rem(square, 8)
      rank = div(square, 8)
      attacker_file = file + df * distance
      attacker_rank = rank + dr * distance

      if attacker_file in 0..7 and attacker_rank in 0..7 do
        attacker_square = attacker_rank * 8 + attacker_file

        for color <- [:white, :black], piece <- [type, :queen] do
          board = Bitboard.put(Bitboard.empty(), attacker_square, {color, piece})
          check!(board, color, square)
          check!(board, opposite(color), square)

          if distance > 1 do
            blocker_square = (rank + dr) * 8 + file + df
            blocked = Bitboard.put(board, blocker_square, {opposite(color), :pawn})
            check!(blocked, color, square)
            check!(blocked, opposite(color), square)
          end
        end
      end
    end
  end

  defp opposite(:white), do: :black
  defp opposite(:black), do: :white

  def scan(boards, fun) do
    Enum.reduce(boards, 0, fn board, count ->
      Enum.reduce([:white, :black], count, fn color, count ->
        Enum.reduce(0..63, count, fn square, count ->
          if fun.(board, color, square), do: count + 1, else: count
        end)
      end)
    end)
  end

  def measure(boards, fun) do
    :erlang.garbage_collect()
    start = System.monotonic_time(:microsecond)
    count = scan(boards, fun)
    {System.monotonic_time(:microsecond) - start, count}
  end

  def median(sorted), do: Enum.at(sorted, div(length(sorted), 2))

  def benchmark!(boards, runs) do
    old = &Bitboard.attacked?/3
    candidate = &Candidate.attacked?/3

    # Warm the JIT and verify the measured subset produces identical results.
    if scan(boards, old) != scan(boards, candidate) do
      raise "Different attack counts during warm-up"
    end

    pairs =
      for run <- 1..runs do
        if rem(run, 2) == 0 do
          new_result = measure(boards, candidate)
          old_result = measure(boards, old)
          {old_result, new_result}
        else
          old_result = measure(boards, old)
          new_result = measure(boards, candidate)
          {old_result, new_result}
        end
      end

    for {{old_us, old_count}, {new_us, new_count}} <- pairs do
      if old_count != new_count, do: raise("Attack counts differ in timed run")

      IO.puts(
        "  current: #{Float.round(old_us / 1_000, 2)} ms | candidate: #{Float.round(new_us / 1_000, 2)} ms"
      )
    end

    current_median = pairs |> Enum.map(fn {{us, _}, _} -> us end) |> Enum.sort() |> median()
    candidate_median = pairs |> Enum.map(fn {_, {us, _}} -> us end) |> Enum.sort() |> median()

    IO.puts("\nCurrent median:   #{Float.round(current_median / 1_000, 2)} ms")
    IO.puts("Candidate median: #{Float.round(candidate_median / 1_000, 2)} ms")
    IO.puts("Candidate/current: #{Float.round(candidate_median / current_median, 3)}x")
  end
end

games = System.get_env("PGN_RAY_BENCH_GAMES", "20") |> String.to_integer()
plies = System.get_env("PGN_RAY_BENCH_PLIES", "80") |> String.to_integer()
runs = System.get_env("PGN_RAY_BENCH_RUNS", "7") |> String.to_integer()

if games < 1 or plies < 2 or plies > 120 or runs < 3 or rem(runs, 2) == 0 do
  raise ArgumentError, "Expected games >= 1, plies 2..120, and odd runs >= 3"
end

path =
  Path.join(System.tmp_dir!(), "openchesslab-ray-bench-#{System.unique_integer([:positive])}.pgn")

try do
  Analysis.PgnLongGameFixture.build_fixture(path, games, plies, 0)

  {:ok, parsed_games} =
    path
    |> File.read!()
    |> Analysis.PgnBatchImporter.parse()

  boards =
    parsed_games
    |> Enum.flat_map(fn game -> [game.initial_position | Enum.map(game.replay, &elem(&1, 1))] end)
    |> Enum.map(&Chess.Bitboard.from_position/1)

  IO.puts(
    "Validating against production Bitboard.attacked?/3 across #{length(boards)} legal positions..."
  )

  Analysis.SlidingRayComparison.validate!(boards)

  sampled_boards =
    boards
    |> Enum.take_every(max(div(length(boards), 100), 1))
    |> Enum.take(100)

  IO.puts("""
  Sliding attack comparison (no database)
  games: #{games}
  plies/game: #{plies}
  legal boards checked: #{length(boards)}
  benchmark boards: #{length(sampled_boards)}
  queries per timed run: #{length(sampled_boards) * 128}
  runs: #{runs}
  """)

  Analysis.SlidingRayComparison.benchmark!(sampled_boards, runs)
after
  File.rm(path)
end
