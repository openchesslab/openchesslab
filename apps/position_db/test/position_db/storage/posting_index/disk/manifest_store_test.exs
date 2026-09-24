defmodule PositionDB.Storage.PostingIndex.Disk.ManifestStoreTest do
  use ExUnit.Case, async: true

  alias PositionDB.Storage.PostingIndex.Disk.Manifest
  alias PositionDB.Storage.PostingIndex.Disk.ManifestStore

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "position-db-posting-manifest-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)

    on_exit(fn ->
      File.rm_rf!(directory)
    end)

    manifest =
      %Manifest{
        key_format_id: <<"chess-position-property-v1">>,
        bucket_count: 65_536
      }

    %{
      directory: directory,
      manifest: manifest
    }
  end

  test "creates and reads a posting manifest", %{
    directory: directory,
    manifest: manifest
  } do
    assert :ok =
             ManifestStore.create(
               directory,
               manifest
             )

    assert ManifestStore.read(directory) ==
             {:ok, manifest}
  end

  test "returns not found when no manifest exists", %{
    directory: directory
  } do
    assert ManifestStore.read(directory) ==
             {:error, :posting_manifest_not_found}
  end

  test "does not overwrite an existing manifest", %{
    directory: directory,
    manifest: manifest
  } do
    assert :ok =
             ManifestStore.create(
               directory,
               manifest
             )

    different =
      %{
        manifest
        | bucket_count: 32
      }

    assert ManifestStore.create(
             directory,
             different
           ) ==
             {:error, :posting_manifest_exists}

    assert ManifestStore.read(directory) ==
             {:ok, manifest}
  end

  test "does not create a file for an invalid manifest", %{
    directory: directory
  } do
    invalid =
      %Manifest{
        key_format_id: <<>>,
        bucket_count: 16
      }

    assert ManifestStore.create(
             directory,
             invalid
           ) ==
             {:error, :invalid_posting_manifest}

    assert ManifestStore.read(directory) ==
             {:error, :posting_manifest_not_found}
  end

  test "propagates invalid persisted manifest data", %{
    directory: directory
  } do
    File.write!(
      Path.join(
        directory,
        "manifest.dat"
      ),
      <<"invalid">>
    )

    assert ManifestStore.read(directory) ==
             {:error, :invalid_posting_manifest}
  end
end
