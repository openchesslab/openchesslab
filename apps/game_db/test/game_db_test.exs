defmodule GameDBTest do
  use ExUnit.Case, async: true

  alias GameDB.Occurrence
  alias GameDB.Storage.Memory

  test "stores and retrieves a canonical game" do
    db =
      GameDB.new(
        Memory,
        Memory.new()
      )

    {db, game_id} =
      GameDB.put(
        db,
        <<"game-a">>,
        :game_a,
        [10, 20, 30]
      )

    assert game_id == 1

    assert GameDB.get(
             db,
             game_id
           ) ==
             {:ok, :game_a}

    assert GameDB.cardinality(db) == 1
  end

  test "returns the existing id for identical canonical content" do
    db =
      GameDB.new(
        Memory,
        Memory.new()
      )

    fingerprint =
      <<"same-content">>

    {db, game_id_1} =
      GameDB.put(
        db,
        fingerprint,
        :canonical_game,
        [10, 20, 30]
      )

    {db, game_id_2} =
      GameDB.put(
        db,
        fingerprint,
        :canonical_game,
        [10, 20, 30]
      )

    assert game_id_1 == game_id_2
    assert GameDB.cardinality(db) == 1
  end

  test "keeps different canonical games separate on fingerprint collision" do
    db =
      GameDB.new(
        Memory,
        Memory.new()
      )

    fingerprint =
      <<"collision">>

    {db, game_id_1} =
      GameDB.put(
        db,
        fingerprint,
        :game_1,
        [10, 20]
      )

    {db, game_id_2} =
      GameDB.put(
        db,
        fingerprint,
        :game_2,
        [30, 40]
      )

    assert game_id_1 != game_id_2

    assert GameDB.find(
             db,
             fingerprint,
             :game_1
           ) ==
             {:ok, game_id_1}

    assert GameDB.find(
             db,
             fingerprint,
             :game_2
           ) ==
             {:ok, game_id_2}
  end

  test "returns not_found for an unknown canonical game" do
    db =
      GameDB.new(
        Memory,
        Memory.new()
      )

    assert GameDB.find(
             db,
             <<"missing">>,
             :missing
           ) ==
             :not_found

    assert GameDB.get(
             db,
             999
           ) ==
             :not_found
  end

  test "returns the ordered position occurrences of a game" do
    db =
      GameDB.new(
        Memory,
        Memory.new()
      )

    {db, game_id} =
      GameDB.put(
        db,
        <<"game">>,
        :game,
        [10, 20, 10]
      )

    assert GameDB.occurrences(
             db,
             game_id
           ) ==
             {:ok,
              [
                Occurrence.new(
                  1,
                  game_id,
                  0,
                  10
                ),
                Occurrence.new(
                  2,
                  game_id,
                  1,
                  20
                ),
                Occurrence.new(
                  3,
                  game_id,
                  2,
                  10
                )
              ]}
  end

  test "retrieves a position occurrence by id" do
    db =
      GameDB.new(
        Memory,
        Memory.new()
      )

    {db, game_id} =
      GameDB.put(
        db,
        <<"game">>,
        :game,
        [10, 20]
      )

    assert GameDB.get_occurrence(
             db,
             2
           ) ==
             {:ok,
              Occurrence.new(
                2,
                game_id,
                1,
                20
              )}
  end

  test "propagates storage errors without changing the database" do
    db =
      GameDB.new(
        Memory,
        Memory.new()
      )

    assert GameDB.put(
             db,
             <<"game">>,
             :game,
             []
           ) ==
             {:error, :missing_initial_position}

    assert GameDB.cardinality(db) == 0
  end
end
