defmodule Analysis.PositionDatabaseTest do
  use ExUnit.Case, async: true

  alias Analysis.PositionDatabase

  alias Chess.Position
  alias Chess.Square

  alias PositionDB.PositionStore
  alias PositionDB.PropertyIndex.Disk, as: PropertyIndexDisk
  alias PositionDB.Query

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "analysis-position-database-#{System.unique_integer([:positive])}"
      )

    on_exit(fn ->
      File.rm_rf!(directory)
    end)

    %{
      directory: directory
    }
  end

  test "creates and reopens a persistent position database",
       %{
         directory: directory
       } do
    assert {:ok, db} =
             create_database(directory)

    position =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("a4"),
        {:white, :pawn}
      )

    {_db, position_id} =
      PositionDB.append(
        db,
        position
      )

    assert {:ok, reopened} =
             PositionDatabase.open(directory)

    assert PositionDB.get(
             reopened,
             position_id
           ) ==
             {:ok, position}

    assert PositionDB.find(
             reopened,
             position
           ) ==
             {:ok, position_id}

    assert Enum.to_list(
             PositionDB.query(
               reopened,
               Query.property(
                 :open_files,
                 :e
               )
             )
           ) ==
             [position_id]
  end

  test "catches up the property index when primary storage is ahead",
       %{
         directory: directory
       } do
    assert {:ok, db} =
             create_database(directory)

    position_1 =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("a4"),
        {:white, :pawn}
      )

    {db, id_1} =
      PositionDB.append(
        db,
        position_1
      )

    position_2 =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("e4"),
        {:white, :pawn}
      )

    assert {:ok, _store, id_2} =
             PositionStore.put(
               db.store,
               position_2
             )

    assert id_2 ==
             id_1 + 1

    assert {:ok, reopened} =
             PositionDatabase.open(directory)

    assert Enum.to_list(
             PositionDB.query(
               reopened,
               Query.property(
                 :open_files,
                 :a
               )
             )
           ) ==
             [id_2]

    assert PropertyIndexDisk.indexed_through(reopened.indexer.index.backend) ==
             id_2
  end

  defp create_database(directory) do
    PositionDatabase.create(
      directory,
      records_per_segment: 3,
      exact_bucket_count: 16,
      property_bucket_count: 16
    )
  end
end
