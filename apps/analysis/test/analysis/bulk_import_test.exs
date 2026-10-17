defmodule Analysis.BulkImportTest do
  use ExUnit.Case, async: false

  alias Analysis.BulkImport
  alias OpenChessLab.Repo

  # Four pump games: kept, below the floor, bullet, kept at the exact floor.
  @kept_blitz """
  [Event "Rated Blitz game"]
  [Site "https://lichess.org/aaaaaaa1"]
  [White "Delta"]
  [Black "Epsilon"]
  [Result "1-0"]
  [WhiteElo "2300"]
  [BlackElo "2250"]
  [TimeControl "180+0"]

  1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 1-0
  """

  @below_floor """
  [Event "Rated Blitz game"]
  [White "Gamma"]
  [Black "Zeta"]
  [Result "0-1"]
  [WhiteElo "2300"]
  [BlackElo "2100"]
  [TimeControl "300+0"]

  1. d4 d5 0-1
  """

  @bullet """
  [Event "Rated Bullet game"]
  [White "Eta"]
  [Black "Theta"]
  [Result "1/2-1/2"]
  [WhiteElo "2500"]
  [BlackElo "2400"]
  [TimeControl "60+0"]

  1. c4 e5 1/2-1/2
  """

  @kept_rapid """
  [Event "Rated Rapid game"]
  [White "Iota"]
  [Black "Kappa"]
  [Result "1/2-1/2"]
  [WhiteElo "2200"]
  [BlackElo "2345"]
  [TimeControl "600+5"]

  1. Nf3 Nf6 2. g3 g6 1/2-1/2
  """

  defp fixture do
    @kept_blitz <> "\n" <> @below_floor <> "\n" <> @bullet <> "\n" <> @kept_rapid <> "\n"
  end

  defp lines(text), do: String.split(text, "\n", trim: false)

  defp header_games(text) do
    Regex.scan(~r/^\[Event /m, text) |> length()
  end

  test "keep_game? applies the rating floor and the bullet exclusion" do
    assert BulkImport.keep_game?(%{"WhiteElo" => "2300", "BlackElo" => "2250"}, 2200)
    # The floor is inclusive on both sides.
    assert BulkImport.keep_game?(%{"WhiteElo" => "2200", "BlackElo" => "2200"}, 2200)
    refute BulkImport.keep_game?(%{"WhiteElo" => "2300", "BlackElo" => "2199"}, 2200)
    # Missing or unparsable ratings never pass.
    refute BulkImport.keep_game?(%{"WhiteElo" => "2300"}, 2200)
    refute BulkImport.keep_game?(%{"WhiteElo" => "2300", "BlackElo" => "?"}, 2200)
    # Bullet is excluded by the event tag and, independently, by the clock.
    refute BulkImport.keep_game?(
             %{
               "WhiteElo" => "2500",
               "BlackElo" => "2400",
               "Event" => "Rated Bullet game",
               "TimeControl" => "300+0"
             },
             2200
           )

    refute BulkImport.keep_game?(
             %{
               "WhiteElo" => "2500",
               "BlackElo" => "2400",
               "Event" => "Rated Blitz game",
               "TimeControl" => "120+1"
             },
             2200
           )
  end

  test "filter_lines keeps only games above the floor and counts the input" do
    {:ok, stats} = Agent.start_link(fn -> %{read: 0, kept: 0, skipped: 0, malformed: 0} end)

    output = filter(lines(fixture()), stats) |> Enum.join("\n")

    assert header_games(output) == 2
    assert output =~ "Delta"
    assert output =~ "Iota"
    refute output =~ "Gamma"
    refute output =~ "Eta"

    assert %{read: 4, kept: 2, skipped: 0, malformed: 0} = final_stats(stats)
  end

  test "skip discards input games even when they would be kept" do
    output = filter(lines(fixture()), nil, skip: 1) |> Enum.join("\n")

    assert header_games(output) == 1
    refute output =~ "Delta"
    assert output =~ "Iota"
  end

  test "limit stops reading after the given number of input games" do
    {:ok, stats} = Agent.start_link(fn -> %{read: 0, kept: 0, skipped: 0, malformed: 0} end)

    output = filter(lines(fixture()), stats, limit: 2) |> Enum.join("\n")

    assert header_games(output) == 1
    assert output =~ "Delta"
    refute output =~ "Iota"
    # The second game was read but filtered; games three and four never were.
    assert %{read: 2, kept: 1} = final_stats(stats)
  end

  test "run/1 imports the kept games into the corpus and reports the rest" do
    dir = System.tmp_dir!()
    path = Path.join(dir, "bulk-import-#{System.unique_integer([:positive])}.pgn")
    File.write!(path, fixture())
    prefix = "bulk-test-#{System.unique_integer([:positive])}"
    on_exit(fn -> File.rm(path) end)

    assert {:ok, summary} = BulkImport.run(path: path, min_rating: 2200, record_id_prefix: prefix)

    on_exit(fn ->
      Repo.query!("DELETE FROM game_records WHERE record_id LIKE $1", [prefix <> "%"])
    end)

    assert summary.read == 4
    assert summary.kept == 2
    assert summary.imported == 2
    assert summary.handed == 2
    assert summary.failure_count == 0
    assert summary.error == nil
    assert summary.source == :ok

    count =
      Repo.query!("SELECT count(*) FROM game_records WHERE record_id LIKE $1", [prefix <> "%"]).rows
      |> List.first()
      |> List.first()

    assert count == 2

    # The imported records carry the kept games' metadata.
    whites =
      Repo.query!(
        "SELECT metadata ->> 'white' FROM game_records WHERE record_id LIKE $1 ORDER BY record_id",
        [prefix <> "%"]
      ).rows
      |> List.flatten()

    assert "Delta" in whites
    assert "Iota" in whites
    refute "Gamma" in whites
  end

  test "a resumed run continues the record-id sequence and never collides" do
    dir = System.tmp_dir!()
    path = Path.join(dir, "bulk-resume-#{System.unique_integer([:positive])}.pgn")
    File.write!(path, fixture())
    prefix = "bulk-resume-#{System.unique_integer([:positive])}"
    on_exit(fn -> File.rm(path) end)

    # First run: grouped mode, ids 1..2.
    assert {:ok, first} = BulkImport.run(path: path, min_rating: 2200, record_id_prefix: prefix)
    assert first.imported == 2

    # Resumed run: same input, ids continue at 3 (offset = first run's kept
    # count) and parallel mode still works.
    assert {:ok, second} =
             BulkImport.run(
               path: path,
               min_rating: 2200,
               record_id_prefix: prefix,
               record_id_offset: 2,
               mode: :parallel,
               concurrency: 2
             )

    assert second.imported == 2
    assert second.failure_count == 0

    on_exit(fn ->
      Repo.query!("DELETE FROM game_records WHERE record_id LIKE $1", [prefix <> "%"])
    end)

    ids =
      Repo.query!(
        "SELECT record_id FROM game_records WHERE record_id LIKE $1 ORDER BY record_id",
        [
          prefix <> "%"
        ]
      ).rows
      |> List.flatten()
      |> Enum.sort()

    assert ids == Enum.map(1..4, fn index -> "#{prefix}-#{index}" end)
  end

  defp filter(lines, stats, opts \\ []) do
    opts =
      opts
      |> Keyword.put_new(:min_rating, 2200)
      |> Keyword.put_new(:progress_every, 0)
      |> then(fn opts -> if stats, do: Keyword.put(opts, :stats, stats), else: opts end)

    BulkImport.filter_lines(lines, opts)
  end

  defp final_stats(stats) do
    value = Agent.get(stats, & &1)
    Agent.stop(stats)
    value
  end
end
