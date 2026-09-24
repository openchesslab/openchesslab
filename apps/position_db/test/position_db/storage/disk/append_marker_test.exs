defmodule PositionDB.Storage.Disk.AppendMarkerTest do
  use ExUnit.Case, async: true

  alias PositionDB.Storage.Disk.AppendMarker

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "position-db-append-marker-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)

    on_exit(fn ->
      File.rm_rf!(directory)
    end)

    %{
      directory: directory
    }
  end

  test "creates and reads an append marker", %{
    directory: directory
  } do
    assert AppendMarker.create(
             directory,
             42
           ) ==
             :ok

    assert AppendMarker.read(directory) ==
             {:ok, 42}

    assert File.read!(
             Path.join(
               directory,
               "append.pending"
             )
           ) ==
             <<42::unsigned-big-64>>
  end

  test "does not overwrite an existing append marker", %{
    directory: directory
  } do
    assert AppendMarker.create(
             directory,
             41
           ) ==
             :ok

    assert AppendMarker.create(
             directory,
             42
           ) ==
             {:error, :append_marker_exists}

    assert AppendMarker.read(directory) ==
             {:ok, 41}
  end

  test "returns none when no append marker exists", %{
    directory: directory
  } do
    assert AppendMarker.read(directory) ==
             :none
  end

  test "rejects an invalid append marker", %{
    directory: directory
  } do
    File.write!(
      Path.join(
        directory,
        "append.pending"
      ),
      <<1, 2, 3>>
    )

    assert AppendMarker.read(directory) ==
             {:error, :invalid_append_marker}
  end

  test "clears an append marker", %{
    directory: directory
  } do
    assert AppendMarker.create(
             directory,
             42
           ) ==
             :ok

    assert AppendMarker.clear(directory) ==
             :ok

    assert AppendMarker.read(directory) ==
             :none
  end

  test "clearing a missing append marker is idempotent", %{
    directory: directory
  } do
    assert AppendMarker.clear(directory) ==
             :ok
  end
end
