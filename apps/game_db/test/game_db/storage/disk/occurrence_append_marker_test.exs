defmodule GameDB.Storage.Disk.OccurrenceAppendMarkerTest do
  use ExUnit.Case, async: true

  alias GameDB.Storage.Disk.OccurrenceAppendMarker

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "game-db-occurrence-marker-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)

    on_exit(fn ->
      File.rm_rf!(directory)
    end)

    %{
      directory: directory
    }
  end

  test "persists complete occurrence recovery information", %{
    directory: directory
  } do
    assert :ok =
             OccurrenceAppendMarker.create(
               directory,
               42,
               100,
               [
                 10,
                 20,
                 10
               ]
             )

    assert OccurrenceAppendMarker.read(directory) ==
             {:ok,
              %{
                game_id: 42,
                first_occurrence_id: 100,
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
             OccurrenceAppendMarker.create(
               directory,
               2,
               5,
               [
                 10,
                 20
               ]
             )

    assert File.read!(
             Path.join(
               directory,
               "occurrence-append.pending"
             )
           ) ==
             <<
               "OCLOCC01",
               2::unsigned-big-64,
               5::unsigned-big-64,
               2::unsigned-big-32,
               10::unsigned-big-64,
               20::unsigned-big-64
             >>
  end

  test "does not overwrite an existing marker", %{
    directory: directory
  } do
    assert :ok =
             OccurrenceAppendMarker.create(
               directory,
               1,
               1,
               [10]
             )

    assert OccurrenceAppendMarker.create(
             directory,
             2,
             2,
             [20]
           ) ==
             {:error, :append_marker_exists}

    assert OccurrenceAppendMarker.read(directory) ==
             {:ok,
              %{
                game_id: 1,
                first_occurrence_id: 1,
                position_ids: [10]
              }}
  end

  test "returns none when no marker exists", %{
    directory: directory
  } do
    assert OccurrenceAppendMarker.read(directory) ==
             :none
  end

  test "rejects a truncated marker", %{
    directory: directory
  } do
    File.write!(
      Path.join(
        directory,
        "occurrence-append.pending"
      ),
      <<
        "OCLOCC01",
        1::unsigned-big-64
      >>
    )

    assert OccurrenceAppendMarker.read(directory) ==
             {:error, :invalid_append_marker}
  end

  test "rejects a marker whose occurrence count does not match its payload", %{
    directory: directory
  } do
    File.write!(
      Path.join(
        directory,
        "occurrence-append.pending"
      ),
      <<
        "OCLOCC01",
        1::unsigned-big-64,
        1::unsigned-big-64,
        2::unsigned-big-32,
        10::unsigned-big-64
      >>
    )

    assert OccurrenceAppendMarker.read(directory) ==
             {:error, :invalid_append_marker}
  end

  test "rejects zero position ids in a persisted marker", %{
    directory: directory
  } do
    File.write!(
      Path.join(
        directory,
        "occurrence-append.pending"
      ),
      <<
        "OCLOCC01",
        1::unsigned-big-64,
        1::unsigned-big-64,
        1::unsigned-big-32,
        0::unsigned-big-64
      >>
    )

    assert OccurrenceAppendMarker.read(directory) ==
             {:error, :invalid_append_marker}
  end

  test "requires an initial position", %{
    directory: directory
  } do
    assert OccurrenceAppendMarker.create(
             directory,
             1,
             1,
             []
           ) ==
             {:error, :missing_initial_position}
  end

  test "rejects invalid ids before creating the marker", %{
    directory: directory
  } do
    assert OccurrenceAppendMarker.create(
             directory,
             0,
             1,
             [10]
           ) ==
             {:error, :invalid_game_id}

    assert OccurrenceAppendMarker.create(
             directory,
             1,
             0,
             [10]
           ) ==
             {:error, :invalid_occurrence_id}

    assert OccurrenceAppendMarker.read(directory) ==
             :none
  end

  test "clears a marker", %{
    directory: directory
  } do
    assert :ok =
             OccurrenceAppendMarker.create(
               directory,
               1,
               1,
               [10]
             )

    assert :ok =
             OccurrenceAppendMarker.clear(directory)

    assert OccurrenceAppendMarker.read(directory) ==
             :none
  end

  test "clearing a missing marker is idempotent", %{
    directory: directory
  } do
    assert OccurrenceAppendMarker.clear(directory) ==
             :ok
  end
end
