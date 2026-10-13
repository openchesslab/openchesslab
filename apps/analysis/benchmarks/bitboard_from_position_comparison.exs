# Compare three ways of converting Chess.Position boards to Chess.Bitboard.
# This is a standalone, database-free benchmark. Production code is unchanged.
# Run from the repository root:
#   mix run --no-start apps/analysis/benchmarks/bitboard_from_position_comparison.exs

Code.require_file(Path.join(__DIR__, "pgn_long_game_fixture.exs"))

defmodule Analysis.BitboardFromPositionComparison do
  @moduledoc false

  import Bitwise

  alias Analysis.PgnBatchImporter
  alias Analysis.PgnLongGameFixture
  alias Chess.Bitboard
  alias Chess.Board
  alias Chess.Position

  @piece_types [:pawn, :knight, :bishop, :rook, :queen, :king]

  # Candidate A: retain Board.pieces/1, but don't clear a square that we know
  # is empty because Board is a tuple with at most one piece per square.
  def without_clear(%Position{board: board}) do
    board
    |> Board.pieces()
    |> Enum.reduce(Bitboard.empty(), fn {square, {color, type}}, result ->
      add_piece(result, square, color, type)
    end)
  end

  # Candidate B: also avoid allocating an intermediate Board.pieces/1 list.
  def single_pass(%Position{board: board}), do: scan(board, 0, Bitboard.empty())

  defp scan(_board, 64, result), do: result

  defp scan(board, square, result) do
    result =
      case elem(board, square) do
        nil -> result
        {color, type} -> add_piece(result, square, color, type)
      end

    scan(board, square + 1, result)
  end

  defp add_piece(board, square, :white, :pawn),
    do: %{board | white_pawns: bor(board.white_pawns, 1 <<< square)}

  defp add_piece(board, square, :white, :knight),
    do: %{board | white_knights: bor(board.white_knights, 1 <<< square)}

  defp add_piece(board, square, :white, :bishop),
    do: %{board | white_bishops: bor(board.white_bishops, 1 <<< square)}

  defp add_piece(board, square, :white, :rook),
    do: %{board | white_rooks: bor(board.white_rooks, 1 <<< square)}

  defp add_piece(board, square, :white, :queen),
    do: %{board | white_queens: bor(board.white_queens, 1 <<< square)}

  defp add_piece(board, square, :white, :king),
    do: %{board | white_king: bor(board.white_king, 1 <<< square)}

  defp add_piece(board, square, :black, :pawn),
    do: %{board | black_pawns: bor(board.black_pawns, 1 <<< square)}

  defp add_piece(board, square, :black, :knight),
    do: %{board | black_knights: bor(board.black_knights, 1 <<< square)}

  defp add_piece(board, square, :black, :bishop),
    do: %{board | black_bishops: bor(board.black_bishops, 1 <<< square)}

  defp add_piece(board, square, :black, :rook),
    do: %{board | black_rooks: bor(board.black_rooks, 1 <<< square)}

  defp add_piece(board, square, :black, :queen),
    do: %{board | black_queens: bor(board.black_queens, 1 <<< square)}

  defp add_piece(board, square, :black, :king),
    do: %{board | black_king: bor(board.black_king, 1 <<< square)}

  def run do
    games = env_integer("BITBOARD_FROM_POSITION_GAMES", 20)
    plies = env_integer("BITBOARD_FROM_POSITION_PLIES", 80)
    repetitions = env_integer("BITBOARD_FROM_POSITION_REPETITIONS", 8)
    runs = env_integer("BITBOARD_FROM_POSITION_RUNS", 7)

    if games < 1 or plies < 2 or plies > 120 or repetitions < 1 or
         runs < 1 or rem(runs, 2) == 0 do
      raise ArgumentError,
            "expected games >= 1, plies 2..120, repetitions >= 1, and odd runs >= 1"
    end

    path =
      Path.join(
        System.tmp_dir!(),
        "openchesslab-from-position-#{System.unique_integer([:positive])}.pgn"
      )

    try do
      PgnLongGameFixture.build_fixture(path, games, plies, 0)
      positions = parse_positions!(File.read!(path), games)

      verify_all!(positions)
      verify_edge_cases!()

      variants = %{
        current: &Bitboard.from_position/1,
        without_clear: &without_clear/1,
        single_pass: &single_pass/1
      }

      # All variants process precisely the same positions, and the checksum
      # prevents accidentally measuring an unused result.
      {_, expected} = measure(positions, repetitions, variants.current)

      Enum.each([:without_clear, :single_pass], fn variant ->
        {_, actual} = measure(positions, repetitions, Map.fetch!(variants, variant))
        if actual != expected, do: raise("Warm-up checksum mismatch: #{variant}")
      end)

      IO.puts("""
      Bitboard.from_position/1 comparison (no database)
      games:                  #{games}
      plies/game:             #{plies}
      legal positions:        #{length(positions)}
      conversions per run:    #{length(positions) * repetitions}
      runs:                   #{runs}
      """)

      # Rotate execution order to reduce warm-up and clock-drift bias.
      orders = [
        [:current, :without_clear, :single_pass],
        [:single_pass, :without_clear, :current],
        [:without_clear, :current, :single_pass]
      ]

      samples =
        Enum.map(1..runs, fn run ->
          order = Enum.at(orders, rem(run - 1, length(orders)))

          timings =
            Map.new(order, fn variant ->
              {microseconds, checksum} =
                measure(positions, repetitions, Map.fetch!(variants, variant))

              if checksum != expected do
                raise "Timed checksum mismatch for #{variant}"
              end

              {variant, microseconds}
            end)

          IO.puts(
            "  current: #{ms(timings.current)} ms | " <>
              "without clear: #{ms(timings.without_clear)} ms | " <>
              "single pass: #{ms(timings.single_pass)} ms"
          )

          timings
        end)

      medians =
        Map.new(Map.keys(variants), fn variant ->
          {variant, samples |> Enum.map(&Map.fetch!(&1, variant)) |> median()}
        end)

      IO.puts("""
      Current median:       #{ms(medians.current)} ms
      Without-clear median: #{ms(medians.without_clear)} ms
      Single-pass median:   #{ms(medians.single_pass)} ms
      Without-clear/current: #{Float.round(medians.without_clear / medians.current, 3)}x
      Single-pass/current:   #{Float.round(medians.single_pass / medians.current, 3)}x
      """)
    after
      File.rm(path)
    end
  end

  defp parse_positions!(pgn, games) do
    case PgnBatchImporter.parse(pgn) do
      {:ok, parsed} when length(parsed) == games ->
        Enum.flat_map(parsed, fn %{initial_position: initial, replay: replay} ->
          [initial | Enum.map(replay, fn {_move, position} -> position end)]
        end)

      result ->
        raise "Unable to parse legal long-game fixture: #{inspect(result)}"
    end
  end

  defp verify_all!(positions) do
    Enum.each(positions, fn position ->
      expected = Bitboard.from_position(position)

      if without_clear(position) != expected do
        raise "without_clear differs from production"
      end

      if single_pass(position) != expected do
        raise "single_pass differs from production"
      end
    end)
  end

  defp verify_edge_cases! do
    verify_all!([Position.new(), Position.starting_position()])

    for square <- 0..63,
        color <- [:white, :black],
        type <- @piece_types do
      position = Position.new() |> Position.put_piece(square, {color, type})
      verify_all!([position])
    end
  end

  defp measure(positions, repetitions, convert) do
    :erlang.garbage_collect()

    :timer.tc(fn ->
      Enum.reduce(1..repetitions, 0, fn _, total ->
        Enum.reduce(positions, total, fn position, acc ->
          acc + :erlang.phash2(convert.(position))
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

  defp ms(microseconds) do
    :erlang.float_to_binary(microseconds / 1_000, decimals: 2)
  end
end

Analysis.BitboardFromPositionComparison.run()
