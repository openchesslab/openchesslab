defmodule PositionDB.Storage.PostingIndex.Disk.Segment.CommitTest do
  use ExUnit.Case, async: true

  alias PositionDB.Storage.PostingIndex.Disk.Segment.Commit
  alias PositionDB.Storage.PostingIndex.Disk.Segment.Layout

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "position-db-posting-segment-commit-#{System.unique_integer([:positive])}"
      )

    segments_directory =
      Layout.segments_directory(directory)

    File.mkdir_p!(segments_directory)

    on_exit(fn ->
      File.rm_rf!(directory)
    end)

    %{
      directory: directory,
      segments_directory: segments_directory
    }
  end

  test "commits a completed next segment", %{
    directory: directory
  } do
    next_path =
      Layout.next_segment_path(
        directory,
        1,
        100
      )

    segment_path =
      Layout.segment_path(
        directory,
        1,
        100
      )

    File.write!(
      next_path,
      <<"completed segment">>
    )

    assert Commit.commit(
             directory,
             1,
             100
           ) ==
             :ok

    refute File.exists?(next_path)

    assert File.read!(segment_path) ==
             <<"completed segment">>
  end

  test "refuses to replace an existing committed segment", %{
    directory: directory
  } do
    next_path =
      Layout.next_segment_path(
        directory,
        1,
        100
      )

    segment_path =
      Layout.segment_path(
        directory,
        1,
        100
      )

    File.write!(
      next_path,
      <<"new segment">>
    )

    File.write!(
      segment_path,
      <<"existing segment">>
    )

    assert Commit.commit(
             directory,
             1,
             100
           ) ==
             {:error, :segment_exists}

    assert File.read!(segment_path) ==
             <<"existing segment">>

    assert File.read!(next_path) ==
             <<"new segment">>
  end

  test "refuses to replace any existing destination entry", %{
    directory: directory
  } do
    next_path =
      Layout.next_segment_path(
        directory,
        1,
        100
      )

    segment_path =
      Layout.segment_path(
        directory,
        1,
        100
      )

    File.write!(
      next_path,
      <<"new segment">>
    )

    File.mkdir!(segment_path)

    assert Commit.commit(
             directory,
             1,
             100
           ) ==
             {:error, :segment_exists}

    assert File.dir?(segment_path)

    assert File.read!(next_path) ==
             <<"new segment">>
  end

  test "returns an error when the next segment is missing", %{
    directory: directory
  } do
    segment_path =
      Layout.segment_path(
        directory,
        1,
        100
      )

    assert Commit.commit(
             directory,
             1,
             100
           ) ==
             {:error, :enoent}

    refute File.exists?(segment_path)
  end

  test "requires the next segment to be a regular file", %{
    directory: directory
  } do
    next_path =
      Layout.next_segment_path(
        directory,
        1,
        100
      )

    segment_path =
      Layout.segment_path(
        directory,
        1,
        100
      )

    File.mkdir!(next_path)

    assert Commit.commit(
             directory,
             1,
             100
           ) ==
             {:error, :not_a_regular_file}

    assert File.dir?(next_path)
    refute File.exists?(segment_path)
  end

  test "commits adjacent ranges to distinct immutable files", %{
    directory: directory
  } do
    first_next =
      Layout.next_segment_path(
        directory,
        1,
        100
      )

    second_next =
      Layout.next_segment_path(
        directory,
        101,
        200
      )

    File.write!(
      first_next,
      <<"first">>
    )

    File.write!(
      second_next,
      <<"second">>
    )

    assert :ok =
             Commit.commit(
               directory,
               1,
               100
             )

    assert :ok =
             Commit.commit(
               directory,
               101,
               200
             )

    assert File.read!(
             Layout.segment_path(
               directory,
               1,
               100
             )
           ) ==
             <<"first">>

    assert File.read!(
             Layout.segment_path(
               directory,
               101,
               200
             )
           ) ==
             <<"second">>
  end
end
