defmodule PositionDB.Storage.Disk.IndexProgressStoreTest do
  use ExUnit.Case, async: true

  alias PositionDB.Storage.Disk.IndexProgressStore

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "position-db-index-progress-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)

    on_exit(fn ->
      File.rm_rf!(directory)
    end)

    %{
      directory: directory
    }
  end

  test "returns none when no progress exists", %{
    directory: directory
  } do
    assert IndexProgressStore.read(directory) ==
             :none
  end

  test "persists an initial zero watermark", %{
    directory: directory
  } do
    assert IndexProgressStore.advance(
             directory,
             0
           ) ==
             :ok

    assert IndexProgressStore.read(directory) ==
             {:ok, 0}
  end

  test "advances durable index progress", %{
    directory: directory
  } do
    assert :ok =
             IndexProgressStore.advance(
               directory,
               10
             )

    assert :ok =
             IndexProgressStore.advance(
               directory,
               42
             )

    assert IndexProgressStore.read(directory) ==
             {:ok, 42}
  end

  test "advancing to the current id is idempotent", %{
    directory: directory
  } do
    assert :ok =
             IndexProgressStore.advance(
               directory,
               42
             )

    assert :ok =
             IndexProgressStore.advance(
               directory,
               42
             )

    assert IndexProgressStore.read(directory) ==
             {:ok, 42}
  end

  test "does not allow progress to move backwards", %{
    directory: directory
  } do
    assert :ok =
             IndexProgressStore.advance(
               directory,
               42
             )

    assert IndexProgressStore.advance(
             directory,
             41
           ) ==
             {:error, {:indexed_through_regression, 42, 41}}

    assert IndexProgressStore.read(directory) ==
             {:ok, 42}
  end

  test "rejects invalid persisted progress", %{
    directory: directory
  } do
    File.write!(
      Path.join(
        directory,
        "indexed-through.dat"
      ),
      <<1, 2, 3>>
    )

    assert IndexProgressStore.read(directory) ==
             {:error, :invalid_index_progress}
  end

  test "rejects invalid progress magic", %{
    directory: directory
  } do
    File.write!(
      Path.join(
        directory,
        "indexed-through.dat"
      ),
      <<
        "INVALID!"::binary,
        1::unsigned-big-16,
        42::unsigned-big-64
      >>
    )

    assert IndexProgressStore.read(directory) ==
             {:error, :invalid_index_progress_magic}
  end

  test "rejects an unsupported progress version", %{
    directory: directory
  } do
    File.write!(
      Path.join(
        directory,
        "indexed-through.dat"
      ),
      <<
        "OCLIDX"::binary,
        0,
        0,
        2::unsigned-big-16,
        42::unsigned-big-64
      >>
    )

    assert IndexProgressStore.read(directory) ==
             {:error, {:unsupported_index_progress_version, 2}}
  end

  test "ignores a stale next file when reading progress", %{
    directory: directory
  } do
    assert :ok =
             IndexProgressStore.advance(
               directory,
               10
             )

    File.write!(
      Path.join(
        directory,
        "indexed-through.next"
      ),
      <<"interrupted update">>
    )

    assert IndexProgressStore.read(directory) ==
             {:ok, 10}
  end

  test "replaces a stale next file on the next advance", %{
    directory: directory
  } do
    assert :ok =
             IndexProgressStore.advance(
               directory,
               10
             )

    File.write!(
      Path.join(
        directory,
        "indexed-through.next"
      ),
      <<"interrupted update">>
    )

    assert :ok =
             IndexProgressStore.advance(
               directory,
               20
             )

    assert IndexProgressStore.read(directory) ==
             {:ok, 20}

    refute File.exists?(
             Path.join(
               directory,
               "indexed-through.next"
             )
           )
  end
end
