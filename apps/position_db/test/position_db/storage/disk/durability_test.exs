defmodule PositionDB.Storage.Disk.DurabilityTest do
  use ExUnit.Case, async: true

  alias PositionDB.Storage.Disk.Durability

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "position-db-durability-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)

    on_exit(fn ->
      File.rm_rf!(root)
    end)

    %{root: root}
  end

  test "syncs an existing directory", %{
    root: root
  } do
    assert Durability.sync_directory(root) ==
             :ok
  end

  test "rejects a missing directory", %{
    root: root
  } do
    missing =
      Path.join(
        root,
        "missing"
      )

    assert Durability.sync_directory(missing) ==
             {:error, :enoent}
  end

  test "rejects a path that is not a directory", %{
    root: root
  } do
    path =
      Path.join(
        root,
        "file"
      )

    File.write!(
      path,
      <<"data">>
    )

    assert Durability.sync_directory(path) ==
             {:error, :not_a_directory}
  end

  test "creates a directory", %{
    root: root
  } do
    directory =
      Path.join(
        root,
        "created"
      )

    assert Durability.create_directory(directory) ==
             :ok

    assert File.dir?(directory)
  end

  test "durably renames sibling directories", %{
    root: root
  } do
    source =
      Path.join(
        root,
        "source"
      )

    destination =
      Path.join(
        root,
        "destination"
      )

    File.mkdir!(source)

    File.write!(
      Path.join(
        source,
        "data"
      ),
      <<"value">>
    )

    assert Durability.rename_sibling(
             source,
             destination
           ) ==
             :ok

    refute File.exists?(source)

    assert File.read!(
             Path.join(
               destination,
               "data"
             )
           ) ==
             <<"value">>
  end

  test "rejects rename across different parent directories", %{
    root: root
  } do
    left =
      Path.join(
        root,
        "left"
      )

    right =
      Path.join(
        root,
        "right"
      )

    File.mkdir!(left)
    File.mkdir!(right)

    source =
      Path.join(
        left,
        "source"
      )

    destination =
      Path.join(
        right,
        "destination"
      )

    File.mkdir!(source)

    assert Durability.rename_sibling(
             source,
             destination
           ) ==
             {:error, :different_parent_directories}

    assert File.dir?(source)
    refute File.exists?(destination)
  end

  test "syncs an existing regular file", %{
    root: root
  } do
    path =
      Path.join(
        root,
        "data"
      )

    File.write!(
      path,
      <<"value">>
    )

    assert Durability.sync_file(path) ==
             :ok

    assert File.read!(path) ==
             <<"value">>
  end

  test "rejects a directory as a regular file", %{
    root: root
  } do
    assert Durability.sync_file(root) ==
             {:error, :not_a_regular_file}
  end

  test "rejects a missing regular file", %{
    root: root
  } do
    path =
      Path.join(
        root,
        "missing"
      )

    assert Durability.sync_file(path) ==
             {:error, :enoent}
  end

  test "durably removes a directory", %{
    root: root
  } do
    directory =
      Path.join(
        root,
        "removed"
      )

    File.mkdir!(directory)

    File.write!(
      Path.join(
        directory,
        "data"
      ),
      <<"value">>
    )

    assert Durability.remove_directory(directory) ==
             :ok

    refute File.exists?(directory)
  end

  test "removing a missing directory is idempotent", %{
    root: root
  } do
    directory =
      Path.join(
        root,
        "missing"
      )

    assert Durability.remove_directory(directory) ==
             :ok
  end

  test "durably replaces a sibling regular file", %{
    root: root
  } do
    source =
      Path.join(
        root,
        "source"
      )

    destination =
      Path.join(
        root,
        "destination"
      )

    File.write!(
      source,
      <<"new">>
    )

    File.write!(
      destination,
      <<"old">>
    )

    assert Durability.replace_sibling_file(
             source,
             destination
           ) ==
             :ok

    refute File.exists?(source)

    assert File.read!(destination) ==
             <<"new">>
  end

  test "rejects file replacement across different parent directories", %{
    root: root
  } do
    left =
      Path.join(
        root,
        "left"
      )

    right =
      Path.join(
        root,
        "right"
      )

    File.mkdir!(left)
    File.mkdir!(right)

    source =
      Path.join(
        left,
        "source"
      )

    destination =
      Path.join(
        right,
        "destination"
      )

    File.write!(
      source,
      <<"new">>
    )

    assert Durability.replace_sibling_file(
             source,
             destination
           ) ==
             {:error, :different_parent_directories}

    assert File.read!(source) ==
             <<"new">>

    refute File.exists?(destination)
  end
end
