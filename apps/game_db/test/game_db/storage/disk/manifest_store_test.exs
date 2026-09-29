defmodule GameDB.Storage.Disk.ManifestStoreTest do
  use ExUnit.Case, async: true

  alias GameDB.Storage.Disk.Manifest
  alias GameDB.Storage.Disk.ManifestStore

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "game-db-manifest-store-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)

    on_exit(fn ->
      File.rm_rf!(directory)
    end)

    manifest = %Manifest{
      record_format_id: <<"game-v1">>,
      fingerprint_format_id: <<"game-sha256-v1">>,
      fingerprint_size: 32,
      canonical_bucket_count: 65_536,
      position_bucket_count: 131_072
    }

    %{
      directory: directory,
      manifest: manifest
    }
  end

  test "creates and reads a manifest", %{
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
             {:error, :manifest_not_found}
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

    different_manifest =
      %{
        manifest
        | canonical_bucket_count: 128
      }

    assert ManifestStore.create(
             directory,
             different_manifest
           ) ==
             {:error, :manifest_exists}

    assert ManifestStore.read(directory) ==
             {:ok, manifest}
  end

  test "does not create a file for an invalid manifest", %{
    directory: directory,
    manifest: manifest
  } do
    invalid_manifest =
      %{
        manifest
        | position_bucket_count: 0
      }

    assert ManifestStore.create(
             directory,
             invalid_manifest
           ) ==
             {:error, :invalid_manifest}

    assert ManifestStore.read(directory) ==
             {:error, :manifest_not_found}
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
             {:error, :invalid_manifest}
  end
end
