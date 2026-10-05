defmodule Analysis.PgnReplayReuseTest do
  use ExUnit.Case, async: false

  alias Analysis.GameContent
  alias Analysis.GameRecord
  alias Analysis.GameRecords
  alias Analysis.GameStart
  alias Analysis.PgnImporter
  alias Analysis.PositionStore
  alias OpenChessLab.Repo

  setup do
    Repo.query!(
      """
      TRUNCATE TABLE
        game_records,
        game_occurrences,
        games,
        position_features,
        positions
      RESTART IDENTITY
      CASCADE
      """,
      []
    )

    :ok
  end

  test "parsed PGN retains the validated replay used to derive its moves and final position" do
    assert {:ok, parsed} =
             PgnImporter.parse("""
             [Event "Replay reuse"]

             1. e4 e5 2. Nf3 Nc6 *
             """)

    assert Enum.map(
             parsed.replay,
             fn {move, _position} ->
               move
             end
           ) ==
             parsed.moves

    assert {
             _last_move,
             last_position
           } =
             List.last(parsed.replay)

    assert last_position ==
             parsed.final_position
  end

  test "parsed import does not load the initial position to replay the game again" do
    record_id =
      unique_record_id()

    assert {:ok, parsed} =
             PgnImporter.parse("""
             [Event "Replay reuse"]

             1. e4 e5 2. Nf3 Nc6 *
             """)

    queries =
      capture_queries(fn ->
        assert {:ok, %GameRecord{} = record} =
                 PgnImporter.import_parsed(
                   record_id,
                   parsed
                 )

        assert GameRecord.id(record) ==
                 record_id
      end)

    refute Enum.any?(
             queries,
             fn query ->
               normalize_query(query) ==
                 "SELECT record FROM positions WHERE id = $1"
             end
           )

    assert {
             :ok,
             _record,
             content,
             occurrences
           } =
             GameRecords.load(record_id)

    assert length(GameContent.moves(content)) ==
             4

    assert length(occurrences) ==
             5
  end

  test "replayed creation rejects replay data for different canonical moves" do
    assert {:ok, e4} =
             PgnImporter.parse("1. e4 *")

    assert {:ok, d4} =
             PgnImporter.parse("1. d4 *")

    initial_position_id =
      PositionStore.append(e4.initial_position)

    content =
      GameContent.new(
        initial_position_id,
        e4.moves
      )

    record_id =
      unique_record_id()

    assert GameRecords.create_replayed(
             record_id,
             content,
             GameStart.standard(),
             %{},
             d4.replay
           ) ==
             {:error,
              {
                :invalid_game,
                :invalid_replay
              }}

    assert GameRecords.get(record_id) ==
             :not_found
  end

  defp capture_queries(fun) do
    telemetry_prefix =
      Repo.config()
      |> Keyword.fetch!(:telemetry_prefix)

    event =
      telemetry_prefix ++
        [:query]

    handler_id =
      {
        __MODULE__,
        make_ref()
      }

    parent =
      self()

    :ok =
      :telemetry.attach(
        handler_id,
        event,
        fn _event, _measurements, metadata, parent ->
          send(
            parent,
            {
              :captured_query,
              metadata.query
            }
          )
        end,
        parent
      )

    try do
      fun.()
      drain_queries([])
    after
      :telemetry.detach(handler_id)
    end
  end

  defp drain_queries(queries) do
    receive do
      {
        :captured_query,
        query
      } ->
        drain_queries([query | queries])
    after
      0 ->
        Enum.reverse(queries)
    end
  end

  defp normalize_query(query) do
    query
    |> String.replace(
      ~r/\s+/,
      " "
    )
    |> String.trim()
  end

  defp unique_record_id do
    "pgn-replay-reuse-" <>
      Base.url_encode64(
        :crypto.strong_rand_bytes(16),
        padding: false
      )
  end
end
