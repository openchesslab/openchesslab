defmodule PositionDB.Storage.Disk.ManifestStoreTest do
  use ExUnit.Case, async: true

  alias PositionDB.Storage.Disk.Manifest
  alias PositionDB.Storage.Disk.ManifestStore

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "position-db-manifest-store-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)

    on_exit(fn ->
      File.rm_rf!(directory)
    end)

    manifest = %Manifest{
      record_format_id: <<"position-v1">>,
      record_size: 67,
      records_per_segment: 1_000_000,
      exact_hash_format_id: <<"hash-v1">>,
      exact_hash_size: 32,
      exact_bucket_count: 65_536
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
        | records_per_segment: 2_000_000
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
        | record_size: 0
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

  test "propagates an invalid persisted manifest magic", %{
    directory: directory,
    manifest: manifest
  } do
    assert {:ok, encoded} =
             Manifest.encode(manifest)

    <<_first, rest::binary>> =
      encoded

    File.write!(
      Path.join(
        directory,
        "manifest.dat"
      ),
      <<0, rest::binary>>
    )

    assert ManifestStore.read(directory) ==
             {:error, :invalid_manifest_magic}
  end
end
