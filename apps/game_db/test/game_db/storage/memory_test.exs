defmodule GameDB.Storage.MemoryTest do
  use ExUnit.Case, async: true

  alias GameDB.Occurrence
  alias GameDB.Storage.Memory

  test "stores and retrieves a game record" do
    storage = Memory.new()

    {:ok, storage, game_id} =
      Memory.append(
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
      Memory.append(
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
      Memory.append(
        storage,
        <<"game-1">>,
        :game_1,
        [10, 20]
      )

    {:ok, storage, game_2} =
      Memory.append(
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
      Memory.append(
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
    assert Memory.append(
             Memory.new(),
             <<"game">>,
             :game,
             []
           ) ==
             {:error, :missing_initial_position}
  end

  test "scans stored game ids" do
    storage = Memory.new()

    {:ok, storage, 1} =
      Memory.append(
        storage,
        <<"game-1">>,
        :game_1,
        [10]
      )

    {:ok, storage, 2} =
      Memory.append(
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
      Memory.append(
        storage,
        <<"game-1">>,
        :game_1,
        [10]
      )

    {:ok, storage, _game_id} =
      Memory.append(
        storage,
        <<"game-2">>,
        :game_2,
        [20]
      )

    assert Memory.cardinality(storage) == 2
  end

  test "finds games with the same fingerprint as candidates" do
    storage = Memory.new()

    fingerprint = <<"same-chess-content">>

    {:ok, storage, game_1} =
      Memory.append(
        storage,
        fingerprint,
        :first_played_game,
        [10, 20, 30]
      )

    {:ok, storage, game_2} =
      Memory.append(
        storage,
        fingerprint,
        :second_played_game,
        [10, 20, 30]
      )

    assert Memory.find_candidates(
             storage,
             fingerprint
           ) ==
             {:ok, [game_1, game_2]}
  end

  test "keeps different fingerprints separate" do
    storage = Memory.new()

    {:ok, storage, game_1} =
      Memory.append(
        storage,
        <<"first">>,
        :game_1,
        [10, 20]
      )

    {:ok, storage, _game_2} =
      Memory.append(
        storage,
        <<"second">>,
        :game_2,
        [30, 40]
      )

    assert Memory.find_candidates(
             storage,
             <<"first">>
           ) ==
             {:ok, [game_1]}

    assert Memory.find_candidates(
             storage,
             <<"missing">>
           ) ==
             {:ok, []}
  end
end
