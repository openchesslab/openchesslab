defmodule Analysis.GameStoreRaceTest do
  @moduledoc """
  Stress test for the intermittent `{:game_store, :invalid_occurrences}`
  failure: concurrent creation of the same canonical game through different
  concrete records, the pattern that intermittently failed in the suite.
  """

  use ExUnit.Case, async: false

  alias Analysis.GameContent
  alias Analysis.GameRecords
  alias Analysis.GameStart
  alias Analysis.PositionStore
  alias Chess.Move
  alias Chess.Position
  alias Chess.Square
  alias OpenChessLab.Repo

  defp move(from, to) do
    Move.new(
      Square.from_algebraic(from),
      Square.from_algebraic(to)
    )
  end

  setup do
    Repo.query!(
      "TRUNCATE TABLE game_records, game_occurrences, games, positions RESTART IDENTITY CASCADE",
      []
    )

    :ok
  end

  test "concurrent creates of the same canonical game never fail or corrupt" do
    content =
      GameContent.new(
        PositionStore.append(Position.starting_position()),
        [move("e2", "e4"), move("e7", "e5")]
      )

    results =
      1..24
      |> Task.async_stream(
        fn index ->
          GameRecords.create(
            "race-record-#{index}",
            content,
            GameStart.standard(),
            %{"white" => "W", "black" => "B"}
          )
        end,
        max_concurrency: 12,
        timeout: 30_000
      )
      |> Enum.to_list()

    invalid_occurrences =
      Enum.filter(results, &match?({:ok, {:error, {:game_store, :invalid_occurrences}}}, &1))

    other_errors =
      Enum.filter(results, fn
        {:ok, {:error, {:game_store, :invalid_occurrences}}} -> false
        {:ok, {:error, _reason}} -> true
        {:exit, _reason} -> true
        _other -> false
      end)

    assert invalid_occurrences == []
    assert other_errors == []

    # The canonical game exists exactly once, with the full occurrence set.
    %{rows: [[games]]} = Repo.query!("SELECT count(*) FROM games")
    assert games == 1

    %{rows: [[occurrences]]} = Repo.query!("SELECT count(*) FROM game_occurrences")
    assert occurrences == 3

    %{rows: [[records]]} = Repo.query!("SELECT count(DISTINCT record_id) FROM game_records")
    assert records == 24

    # Reading back through the validating load path agrees.
    assert {:ok, _record, _content, occurrences} =
             GameRecords.load("race-record-1")

    assert length(occurrences) == 3
  end

  test "concurrent create plus load of the same game stays consistent" do
    content =
      GameContent.new(
        PositionStore.append(Position.starting_position()),
        [move("e2", "e4"), move("e7", "e5")]
      )

    tasks =
      [
        Task.async(fn ->
          GameRecords.create(
            "race-load-record",
            content,
            GameStart.standard(),
            %{"white" => "W", "black" => "B"}
          )
        end),
        Task.async(fn ->
          GameRecords.load("race-load-record")
        end)
      ]

    [create_result, load_result] = Task.await_many(tasks, 30_000)

    assert {:ok, _record} = create_result
    # The load either legitimately misses the not-yet-created record or
    # returns the full valid game; it must never surface invalid occurrences.
    case load_result do
      :not_found -> :ok
      {:ok, _record, _content, occurrences} -> assert length(occurrences) == 3
      other -> flunk("unexpected load result: #{inspect(other)}")
    end
  end
end
