defmodule Analysis.GameDatabaseTest do
  use ExUnit.Case, async: true

  alias Analysis.GameContent
  alias Analysis.GameDatabase
  alias Analysis.GameFingerprint
  alias GameDB.Occurrence

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "analysis-game-database-#{System.unique_integer([:positive])}"
      )

    on_exit(fn ->
      File.rm_rf!(directory)
    end)

    %{
      directory: directory
    }
  end

  test "creates and reopens a persistent game database",
       %{
         directory: directory
       } do
    assert {:ok, db} =
             create_database(directory)

    content =
      GameContent.new(10)

    assert {:ok, fingerprint} =
             GameFingerprint.for_content(content)

    {db, game_id} =
      GameDB.put(
        db,
        fingerprint,
        content,
        [10]
      )

    assert game_id == 1
    assert GameDB.cardinality(db) == 1

    assert {:ok, reopened} =
             GameDatabase.open(directory)

    assert GameDB.get(
             reopened,
             game_id
           ) ==
             {:ok, content}

    assert GameDB.find(
             reopened,
             fingerprint,
             content
           ) ==
             {:ok, game_id}

    assert GameDB.occurrences(
             reopened,
             game_id
           ) ==
             {:ok,
              [
                Occurrence.new(
                  1,
                  game_id,
                  0,
                  10
                )
              ]}
  end

  test "open_or_create creates a database when none exists",
       %{
         directory: directory
       } do
    assert {:ok, db} =
             GameDatabase.open_or_create(
               directory,
               bucket_count: 4,
               position_bucket_count: 4
             )

    assert GameDB.cardinality(db) == 0
  end

  test "open_or_create reopens an existing database using the persisted layout",
       %{
         directory: directory
       } do
    assert {:ok, db} =
             create_database(directory)

    content =
      GameContent.new(10)

    assert {:ok, fingerprint} =
             GameFingerprint.for_content(content)

    {_db, game_id} =
      GameDB.put(
        db,
        fingerprint,
        content,
        [10]
      )

    assert {:ok, reopened} =
             GameDatabase.open_or_create(
               directory,
               bucket_count: 999,
               position_bucket_count: 999
             )

    assert GameDB.get(
             reopened,
             game_id
           ) ==
             {:ok, content}
  end

  defp create_database(directory) do
    GameDatabase.create(
      directory,
      bucket_count: 4,
      position_bucket_count: 4
    )
  end
end
