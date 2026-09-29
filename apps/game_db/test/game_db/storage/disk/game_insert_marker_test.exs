defmodule GameDB.Storage.Disk.GameInsertMarkerTest do
  use ExUnit.Case, async: true

  alias GameDB.Storage.Disk.GameInsertMarker

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "game-db-game-insert-marker-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)

    on_exit(fn ->
      File.rm_rf!(directory)
    end)

    %{
      directory: directory
    }
  end

  test "persists complete game insert recovery information", %{
    directory: directory
  } do
    assert :ok =
             GameInsertMarker.create(
               directory,
               42,
               [
                 10,
                 20,
                 10
               ]
             )

    assert GameInsertMarker.read(directory) ==
             {:ok,
              %{
                game_id: 42,
                position_ids: [
                  10,
                  20,
                  10
                ]
              }}
  end

  test "uses a stable binary format", %{
    directory: directory
  } do
    assert :ok =
             GameInsertMarker.create(
               directory,
               2,
               [
                 10,
                 20
               ]
             )

    assert File.read!(
             Path.join(
               directory,
               "game-insert.pending"
             )
           ) ==
             <<
               "OCLGIN01",
               2::unsigned-big-64,
               2::unsigned-big-32,
               10::unsigned-big-64,
               20::unsigned-big-64
             >>
  end

  test "does not overwrite an existing marker", %{
    directory: directory
  } do
    assert :ok =
             GameInsertMarker.create(
               directory,
               1,
               [10]
             )

    assert GameInsertMarker.create(
             directory,
             2,
             [20]
           ) ==
             {:error, :append_marker_exists}

    assert GameInsertMarker.read(directory) ==
             {:ok,
              %{
                game_id: 1,
                position_ids: [10]
              }}
  end

  test "returns none when no marker exists", %{
    directory: directory
  } do
    assert GameInsertMarker.read(directory) ==
             :none
  end

  test "rejects a truncated marker", %{
    directory: directory
  } do
    File.write!(
      Path.join(
        directory,
        "game-insert.pending"
      ),
      <<
        "OCLGIN01",
        1::unsigned-big-64
      >>
    )

    assert GameInsertMarker.read(directory) ==
             {:error, :invalid_game_insert_marker}
  end

  test "rejects a marker whose occurrence count does not match its payload", %{
    directory: directory
  } do
    File.write!(
      Path.join(
        directory,
        "game-insert.pending"
      ),
      <<
        "OCLGIN01",
        1::unsigned-big-64,
        2::unsigned-big-32,
        10::unsigned-big-64
      >>
    )

    assert GameInsertMarker.read(directory) ==
             {:error, :invalid_game_insert_marker}
  end

  test "rejects zero position ids in a persisted marker", %{
    directory: directory
  } do
    File.write!(
      Path.join(
        directory,
        "game-insert.pending"
      ),
      <<
        "OCLGIN01",
        1::unsigned-big-64,
        1::unsigned-big-32,
        0::unsigned-big-64
      >>
    )

    assert GameInsertMarker.read(directory) ==
             {:error, :invalid_game_insert_marker}
  end

  test "requires an initial position", %{
    directory: directory
  } do
    assert GameInsertMarker.create(
             directory,
             1,
             []
           ) ==
             {:error, :missing_initial_position}
  end

  test "rejects invalid ids before creating the marker", %{
    directory: directory
  } do
    assert GameInsertMarker.create(
             directory,
             0,
             [10]
           ) ==
             {:error, :invalid_game_id}

    assert GameInsertMarker.create(
             directory,
             1,
             [0]
           ) ==
             {:error, :invalid_position_ids}

    assert GameInsertMarker.read(directory) ==
             :none
  end

  test "clears a marker", %{
    directory: directory
  } do
    assert :ok =
             GameInsertMarker.create(
               directory,
               1,
               [10]
             )

    assert :ok =
             GameInsertMarker.clear(directory)

    assert GameInsertMarker.read(directory) ==
             :none
  end

  test "clearing a missing marker is idempotent", %{
    directory: directory
  } do
    assert GameInsertMarker.clear(directory) ==
             :ok
  end
end
