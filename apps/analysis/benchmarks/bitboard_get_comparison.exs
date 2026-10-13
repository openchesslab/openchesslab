# Compare current Chess.Bitboard.get/2 against direct bitboard field checks.
# Does not start the application or access PostgreSQL.
# From the repository root:
#   mix run --no-start apps/analysis/benchmarks/bitboard_get_comparison.exs

Code.require_file(Path.join(__DIR__, "pgn_long_game_fixture.exs"))

defmodule Analysis.BitboardGetComparison do
  @moduledoc false

  import Bitwise

  alias Analysis.PgnBatchImporter
  alias Analysis.PgnLongGameFixture
  alias Chess.Bitboard

  def candidate_get(board, square) when square in 0..63 do
    mask = 1 <<< square

    cond do
      (board.white_pawns &&& mask) != 0 -> {:white, :pawn}
      (board.white_knights &&& mask) != 0 -> {:white, :knight}
      (board.white_bishops &&& mask) != 0 -> {:white, :bishop}
      (board.white_rooks &&& mask) != 0 -> {:white, :rook}
      (board.white_queens &&& mask) != 0 -> {:white, :queen}
      (board.white_king &&& mask) != 0 -> {:white, :king}
      (board.black_pawns &&& mask) != 0 -> {:black, :pawn}
      (board.black_knights &&& mask) != 0 -> {:black, :knight}
      (board.black_bishops &&& mask) != 0 -> {:black, :bishop}
      (board.black_rooks &&& mask) != 0 -> {:black, :rook}
      (board.black_queens &&& mask) != 0 -> {:black, :queen}
      (board.black_king &&& mask) != 0 -> {:black, :king}
      true -> nil
    end
  end

  def run do
    games = env_integer("BITBOARD_GET_BENCH_GAMES", 20)
    plies = env_integer("BITBOARD_GET_BENCH_PLIES", 80)
    runs = env_integer("BITBOARD_GET_BENCH_RUNS", 7)
    repetitions = env_integer("BITBOARD_GET_BENCH_REPETITIONS", 12)

    if games < 1 or plies < 2 or plies > 120 or runs < 1 or rem(runs, 2) == 0 or
         repetitions < 1 do
      raise ArgumentError,
            "expected games >= 1, plies 2..120, odd runs >= 1 and repetitions >= 1"
    end

    path =
      Path.join(
        System.tmp_dir!(),
        "openchesslab-bitboard-get-#{System.unique_integer([:positive])}.pgn"
      )

    try do
      PgnLongGameFixture.build_fixture(path, games, plies, 0)
      pgn = File.read!(path)

      positions =
        case PgnBatchImporter.parse(pgn) do
          {:ok, parsed} when length(parsed) == games ->
            Enum.flat_map(parsed, fn %{initial_position: initial, replay: replay} ->
              [initial | Enum.map(replay, fn {_move, position} -> position end)]
            end)

          result ->
            raise "Unable to parse the fixture: #{inspect(result)}"
        end

      boards = Enum.map(positions, &Bitboard.from_position/1)
      verify!(boards)
      verify_edge_cases!()

      sample_stride = max(div(length(boards), 100), 1)
      timed_boards = boards |> Enum.take_every(sample_stride) |> Enum.take(100)
      calls = length(timed_boards) * 64 * repetitions

      IO.puts("""
      Bitboard.get/2 comparison (no database)

      games:              #{games}
      plies/game:         #{plies}
      legal boards:       #{length(boards)}
      timed boards:       #{length(timed_boards)}
      lookups per run:    #{calls}
      runs:               #{runs}
      """)

      # Warm up both implementations before the timed runs.
      {_, expected} = measure(timed_boards, repetitions, &Bitboard.get/2)
      {_, ^expected} = measure(timed_boards, repetitions, &candidate_get/2)

      timings =
        Enum.map(1..runs, fn run ->
          {current, candidate} =
            if rem(run, 2) == 1 do
              {current_us, current_sum} =
                measure(timed_boards, repetitions, &Bitboard.get/2)

              {candidate_us, ^current_sum} =
                measure(timed_boards, repetitions, &candidate_get/2)

              {current_us, candidate_us}
            else
              {candidate_us, candidate_sum} =
                measure(timed_boards, repetitions, &candidate_get/2)

              {current_us, ^candidate_sum} =
                measure(timed_boards, repetitions, &Bitboard.get/2)

              {current_us, candidate_us}
            end

          IO.puts("  current: #{format_ms(current)} ms | candidate: #{format_ms(candidate)} ms")

          {current, candidate}
        end)

      current_median = timings |> Enum.map(&elem(&1, 0)) |> median()
      candidate_median = timings |> Enum.map(&elem(&1, 1)) |> median()

      IO.puts("""

      Current median:   #{format_ms(current_median)} ms
      Candidate median: #{format_ms(candidate_median)} ms
      Candidate/current: #{Float.round(candidate_median / current_median, 3)}x
      """)
    after
      File.rm(path)
    end
  end

  defp verify!(boards) do
    Enum.each(boards, fn board ->
      Enum.each(0..63, fn square ->
        current = Bitboard.get(board, square)
        candidate = candidate_get(board, square)

        if current != candidate do
          raise "get mismatch at square #{square}: #{inspect(current)} vs #{inspect(candidate)}"
        end
      end)
    end)
  end

  defp verify_edge_cases! do
    empty = Bitboard.empty()
    assert_same!(empty)

    for square <- 0..63,
        color <- [:white, :black],
        type <- [:pawn, :knight, :bishop, :rook, :queen, :king] do
      board = Bitboard.put(empty, square, {color, type})
      assert_same!(board)
    end

    # The original function prioritizes white pawn through black king when
    # an invalid bitboard contains multiple pieces at the same square.
    mask = 1 <<< 28

    overlap = %{
      empty
      | white_pawns: mask,
        white_knights: mask,
        white_bishops: mask,
        white_rooks: mask,
        white_queens: mask,
        white_king: mask,
        black_pawns: mask,
        black_knights: mask,
        black_bishops: mask,
        black_rooks: mask,
        black_queens: mask,
        black_king: mask
    }

    assert_same!(overlap)
    true = candidate_get(overlap, 28) == {:white, :pawn}
  end

  defp assert_same!(board) do
    verify!([board])
  end

  defp measure(boards, repetitions, getter) do
    :timer.tc(fn ->
      Enum.reduce(1..repetitions, 0, fn _, total ->
        Enum.reduce(boards, total, fn board, total ->
          Enum.reduce(0..63, total, fn square, total ->
            if is_nil(getter.(board, square)), do: total, else: total + 1
          end)
        end)
      end)
    end)
  end

  defp env_integer(key, default) do
    key |> System.get_env(Integer.to_string(default)) |> String.to_integer()
  end

  defp median(values) do
    values |> Enum.sort() |> Enum.at(div(length(values), 2))
  end

  defp format_ms(microseconds) do
    :erlang.float_to_binary(microseconds / 1_000, decimals: 2)
  end
end

Analysis.BitboardGetComparison.run()
