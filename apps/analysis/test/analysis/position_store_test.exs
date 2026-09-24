defmodule Analysis.PositionStoreTest do
  use ExUnit.Case, async: false

  alias Analysis.PositionStore
  alias Chess.Position

  test "appends and gets a position" do
    position = Position.starting_position()

    position_id = PositionStore.append(position)

    assert {:ok, ^position} = PositionStore.get(position_id)
  end

  test "returns not_found for an unknown position" do
    assert :not_found = PositionStore.get(999_999_999)
  end

  test "reuses the id of an existing position" do
    position = Position.starting_position()

    first_id = PositionStore.append(position)
    second_id = PositionStore.append(position)

    assert second_id == first_id
  end

  test "initializes from persistent storage" do
    directory =
      Path.join(
        System.tmp_dir!(),
        "analysis-position-store-#{System.unique_integer([:positive])}"
      )

    on_exit(fn ->
      File.rm_rf!(directory)
    end)

    opts = [
      directory: directory,
      records_per_segment: 3,
      exact_bucket_count: 16,
      property_bucket_count: 16
    ]

    assert {:ok, db} =
             PositionStore.init(opts)

    position =
      Position.starting_position()

    {_db, position_id} =
      PositionDB.append(
        db,
        position
      )

    assert {:ok, reopened} =
             PositionStore.init(opts)

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
  end
end
