defmodule Analysis.GameRecordsBatchTest do
  use ExUnit.Case, async: false

  alias Analysis.GameRecord
  alias Analysis.GameRecords
  alias Analysis.GameStart
  alias Analysis.PositionStore
  alias Chess.Move
  alias Chess.Position
  alias Chess.Square
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
      RESTART IDENTITY CASCADE
      """,
      []
    )

    :ok
  end

  test "an empty batch is a no-op" do
    assert GameRecords.create_replayed_many([]) == {:ok, []}
    assert counts() == [0, 0, 0, 0, 0]
  end

  test "persists unique and duplicate games with ordered positions and metadata" do
    first_moves = [move("e2", "e4"), move("e7", "e5")]
    second_moves = [move("d2", "d4")]

    entries = [
      entry("batch-first", first_moves, "First"),
      entry("batch-second", second_moves, "Second"),
      entry("batch-third", first_moves, "Third")
    ]

    assert {:ok, [first, second, third]} = GameRecords.create_replayed_many(entries)

    assert Enum.map([first, second, third], &GameRecord.id/1) ==
             ["batch-first", "batch-second", "batch-third"]

    assert first.game_id == third.game_id
    refute first.game_id == second.game_id
    assert Enum.slice(counts(), 2, 3) == [2, 5, 3]

    for {record, {record_id, _initial, moves, start, metadata, replay}} <-
          Enum.zip([first, second, third], entries) do
      assert GameRecords.get(record_id) == {:ok, record}
      assert record.start == start
      assert record.metadata == metadata

      assert {:ok, ^record, content, occurrences} = GameRecords.load(record_id)
      assert content.moves == moves
      assert Enum.map(occurrences, & &1.ply) == Enum.to_list(0..length(moves))

      expected_positions = [Position.starting_position() | Enum.map(replay, &elem(&1, 1))]

      for {occurrence, expected_position} <- Enum.zip(occurrences, expected_positions) do
        assert PositionStore.get(occurrence.position_id) == {:ok, expected_position}
      end
    end

    [positions, features, _games, _occurrences, _records] = counts()
    assert positions == features
  end

  test "retains custom initial positions and fullmove numbers" do
    initial =
      Position.new()
      |> Position.put_piece(Square.from_algebraic("e1"), {:white, :king})
      |> Position.put_piece(Square.from_algebraic("e8"), {:black, :king})
      |> Position.put_piece(Square.from_algebraic("h1"), {:white, :rook})

    rook_move = move("h1", "h2")
    {:ok, next_position} = Position.apply_move(initial, rook_move)
    start = GameStart.new(37)

    item =
      {"custom-start", initial, [rook_move], start, %{"event" => "FEN"},
       [{rook_move, next_position}]}

    assert {:ok, [record]} = GameRecords.create_replayed_many([item])
    assert record.start == start
    assert {:ok, ^record, content, occurrences} = GameRecords.load(record.id)
    assert content.moves == [rook_move]
    assert Enum.map(occurrences, & &1.ply) == [0, 1]

    assert [initial_occurrence, next_occurrence] = occurrences
    assert PositionStore.get(initial_occurrence.position_id) == {:ok, initial}
    assert PositionStore.get(next_occurrence.position_id) == {:ok, next_position}
  end

  test "rejects duplicate record ids in the batch before writing anything" do
    entries = [
      entry("same-id", [move("e2", "e4")], "First"),
      entry("same-id", [move("d2", "d4")], "Second")
    ]

    assert GameRecords.create_replayed_many(entries) ==
             {:error, {2, :duplicate_record_id}}

    assert counts() == [0, 0, 0, 0, 0]
  end

  test "rejects a mismatched replay before writing anything" do
    valid = entry("valid-before-invalid", [move("e2", "e4")], "First")

    {id, initial, moves, start, metadata, _replay} =
      entry("invalid-replay", [move("d2", "d4")], "Second")

    invalid = {id, initial, moves, start, metadata, [{move("e2", "e4"), initial}]}

    assert GameRecords.create_replayed_many([valid, invalid]) ==
             {:error, {2, {:invalid_game, :invalid_replay}}}

    assert counts() == [0, 0, 0, 0, 0]
  end

  test "rejects invalid metadata and record ids without writing" do
    {id, initial, moves, start, _metadata, replay} =
      entry("bad-metadata", [move("e2", "e4")], "Event")

    assert GameRecords.create_replayed_many([
             {id, initial, moves, start, %{event: "Bad"}, replay}
           ]) == {:error, {1, :invalid_metadata}}

    assert GameRecords.create_replayed_many([
             {"", initial, moves, start, %{}, replay}
           ]) == {:error, {1, :invalid_record_id}}

    assert GameRecords.create_replayed_many(:not_a_list) == {:error, :invalid_batch}
    assert counts() == [0, 0, 0, 0, 0]
  end

  test "a conflict on the second record rolls back the entire group" do
    {existing_id, initial, moves, start, metadata, replay} =
      entry("already-present", [move("c2", "c4")], "Existing")

    assert {:ok, existing} =
             GameRecords.create_replayed(existing_id, initial, moves, start, metadata, replay)

    before_counts = counts()
    first = entry("must-rollback", [move("f2", "f4")], "New")
    second = entry(existing_id, [move("g2", "g4")], "Conflict")

    assert GameRecords.create_replayed_many([first, second]) ==
             {:error, {2, :already_exists}}

    assert counts() == before_counts
    assert GameRecords.get("must-rollback") == :not_found
    assert GameRecords.get(existing_id) == {:ok, existing}

    {:ok, after_f4} = Position.apply_move(Position.starting_position(), move("f2", "f4"))
    assert PositionStore.find(after_f4) == :not_found
  end

  test "concurrent groups reuse canonical game identity" do
    moves = [move("e2", "e4"), move("e7", "e5")]

    tasks =
      for index <- 1..2 do
        Task.async(fn ->
          GameRecords.create_replayed_many([
            entry("parallel-batch-#{index}", moves, "Concurrent")
          ])
        end)
      end

    assert [{:ok, [first]}, {:ok, [second]}] = Task.await_many(tasks, 30_000)
    assert first.game_id == second.game_id
    assert Enum.slice(counts(), 2, 3) == [1, 3, 2]
  end

  defp entry(record_id, moves, event) do
    initial = Position.starting_position()

    {replay, _final_position} =
      Enum.map_reduce(moves, initial, fn move, position ->
        {:ok, next_position} = Position.apply_move(position, move)
        {{move, next_position}, next_position}
      end)

    {record_id, initial, moves, GameStart.standard(), %{"event" => event}, replay}
  end

  defp move(from, to) do
    Move.new(Square.from_algebraic(from), Square.from_algebraic(to))
  end

  defp counts do
    [row] =
      Repo.query!(
        """
        SELECT
          (SELECT count(*) FROM positions),
          (SELECT count(*) FROM position_features),
          (SELECT count(*) FROM games),
          (SELECT count(*) FROM game_occurrences),
          (SELECT count(*) FROM game_records)
        """,
        []
      ).rows

    row
  end
end
