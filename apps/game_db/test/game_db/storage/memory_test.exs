defmodule GameDB.Storage.MemoryTest do
  use ExUnit.Case, async: true

  alias GameDB.Occurrence
  alias GameDB.Storage.Memory

  test "stores and retrieves a game record" do
    storage = Memory.new()

    {:ok, storage, game_id} =
      Memory.put(
        storage,
        <<"game-a">>,
        :game_a,
        [10, 20, 30]
      )

    assert game_id == 1
    assert Memory.get(storage, game_id) == {:ok, :game_a}
  end

  test "stores every position occurrence in ply order" do
    storage = Memory.new()

    {:ok, storage, game_id} =
      Memory.put(
        storage,
        <<"game">>,
        :game,
        [10, 20, 10]
      )

    assert Memory.occurrences(
             storage,
             game_id
           ) ==
             {:ok,
              [
                Occurrence.new(1, 1, 0, 10),
                Occurrence.new(2, 1, 1, 20),
                Occurrence.new(3, 1, 2, 10)
              ]}
  end

  test "occurrence ids remain unique across games" do
    storage = Memory.new()

    {:ok, storage, game_1} =
      Memory.put(
        storage,
        <<"game-1">>,
        :game_1,
        [10, 20]
      )

    {:ok, storage, game_2} =
      Memory.put(
        storage,
        <<"game-2">>,
        :game_2,
        [30, 40]
      )

    assert {:ok, game_1_occurrences} =
             Memory.occurrences(
               storage,
               game_1
             )

    assert {:ok, game_2_occurrences} =
             Memory.occurrences(
               storage,
               game_2
             )

    assert Enum.map(
             game_1_occurrences,
             & &1.id
           ) == [1, 2]

    assert Enum.map(
             game_2_occurrences,
             & &1.id
           ) == [3, 4]
  end

  test "retrieves an occurrence by its stable id" do
    storage = Memory.new()

    {:ok, storage, _game_id} =
      Memory.put(
        storage,
        <<"game">>,
        :game,
        [10, 20]
      )

    assert Memory.get_occurrence(
             storage,
             2
           ) ==
             {:ok,
              Occurrence.new(
                2,
                1,
                1,
                20
              )}
  end

  test "requires an initial position occurrence" do
    assert Memory.put(
             Memory.new(),
             <<"game">>,
             :game,
             []
           ) ==
             {:error, :missing_initial_position}
  end

  test "finds every occurrence of a position within a game" do
    storage =
      Memory.new()

    {:ok, storage, game_id} =
      Memory.put(
        storage,
        <<"game">>,
        :game,
        [10, 20, 10]
      )

    assert {
             :ok,
             occurrences
           } =
             Memory.occurrences_by_position_id(
               storage,
               10
             )

    assert MapSet.new(occurrences) ==
             MapSet.new([
               Occurrence.new(
                 1,
                 game_id,
                 0,
                 10
               ),
               Occurrence.new(
                 3,
                 game_id,
                 2,
                 10
               )
             ])
  end

  test "finds occurrences of a position across games" do
    storage =
      Memory.new()

    {:ok, storage, game_1} =
      Memory.put(
        storage,
        <<"game-1">>,
        :game_1,
        [10, 20]
      )

    {:ok, storage, game_2} =
      Memory.put(
        storage,
        <<"game-2">>,
        :game_2,
        [30, 10]
      )

    assert {
             :ok,
             occurrences
           } =
             Memory.occurrences_by_position_id(
               storage,
               10
             )

    assert MapSet.new(occurrences) ==
             MapSet.new([
               Occurrence.new(
                 1,
                 game_1,
                 0,
                 10
               ),
               Occurrence.new(
                 4,
                 game_2,
                 1,
                 10
               )
             ])
  end

  test "returns no occurrences for an unknown position" do
    assert Memory.occurrences_by_position_id(
             Memory.new(),
             999
           ) ==
             {:ok, []}
  end

  test "scans occurrences of a position incrementally" do
    storage =
      Memory.new()

    {:ok, storage, game_1} =
      Memory.put(
        storage,
        <<"game-1">>,
        :game_1,
        [10, 20, 10]
      )

    {:ok, storage, game_2} =
      Memory.put(
        storage,
        <<"game-2">>,
        :game_2,
        [30, 10]
      )

    scan =
      Memory.scan_occurrences(
        storage,
        10
      )

    assert {:ok, first, scan} =
             Memory.scan_occurrences_next(scan)

    assert {:ok, second, scan} =
             Memory.scan_occurrences_next(scan)

    assert {:ok, third, scan} =
             Memory.scan_occurrences_next(scan)

    assert :done =
             Memory.scan_occurrences_next(scan)

    assert MapSet.new([
             first,
             second,
             third
           ]) ==
             MapSet.new([
               Occurrence.new(
                 1,
                 game_1,
                 0,
                 10
               ),
               Occurrence.new(
                 3,
                 game_1,
                 2,
                 10
               ),
               Occurrence.new(
                 5,
                 game_2,
                 1,
                 10
               )
             ])
  end

  test "finishes an occurrence scan for an unknown position" do
    scan =
      Memory.scan_occurrences(
        Memory.new(),
        999
      )

    assert :done =
             Memory.scan_occurrences_next(scan)
  end

  test "scans stored game ids" do
    storage = Memory.new()

    {:ok, storage, 1} =
      Memory.put(
        storage,
        <<"game-1">>,
        :game_1,
        [10]
      )

    {:ok, storage, 2} =
      Memory.put(
        storage,
        <<"game-2">>,
        :game_2,
        [20]
      )

    scan = Memory.scan(storage)

    assert {:ok, 1, scan} =
             Memory.scan_next(scan)

    assert {:ok, 2, scan} =
             Memory.scan_next(scan)

    assert :done =
             Memory.scan_next(scan)
  end

  test "returns the number of games" do
    storage = Memory.new()

    {:ok, storage, _game_id} =
      Memory.put(
        storage,
        <<"game-1">>,
        :game_1,
        [10]
      )

    {:ok, storage, _game_id} =
      Memory.put(
        storage,
        <<"game-2">>,
        :game_2,
        [20]
      )

    assert Memory.cardinality(storage) == 2
  end

  test "returns the existing id for the same canonical game" do
    storage = Memory.new()

    fingerprint = <<"same-chess-content">>

    {:ok, storage, game_id_1} =
      Memory.put(
        storage,
        fingerprint,
        :canonical_game,
        [10, 20, 30]
      )

    {:ok, storage, game_id_2} =
      Memory.put(
        storage,
        fingerprint,
        :canonical_game,
        [10, 20, 30]
      )

    assert game_id_1 == game_id_2
    assert Memory.cardinality(storage) == 1
  end

  test "keeps different games with the same fingerprint separate" do
    storage = Memory.new()

    fingerprint = <<"collision">>

    {:ok, storage, game_id_1} =
      Memory.put(
        storage,
        fingerprint,
        :game_1,
        [10, 20]
      )

    {:ok, storage, game_id_2} =
      Memory.put(
        storage,
        fingerprint,
        :game_2,
        [30, 40]
      )

    assert game_id_1 != game_id_2

    assert Memory.find(
             storage,
             fingerprint,
             :game_1
           ) ==
             {:ok, game_id_1}

    assert Memory.find(
             storage,
             fingerprint,
             :game_2
           ) ==
             {:ok, game_id_2}
  end
end
