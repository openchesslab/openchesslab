defmodule PositionDB.PropertyIndex.Disk.CatchUpTest do
  use ExUnit.Case, async: true

  alias PositionDB.PositionIndexer
  alias PositionDB.PositionStore
  alias PositionDB.PropertyIndex
  alias PositionDB.PropertyIndex.Disk
  alias PositionDB.PropertyIndex.Disk.CatchUp
  alias PositionDB.Storage.Disk.IndexProgressStore
  alias PositionDB.Storage.PostingIndex.Disk.Entry
  alias PositionDB.Storage.PostingIndex.Disk.Layout

  defmodule TestCodec do
    @behaviour PositionDB.Storage.PropertyKeyCodec

    @impl PositionDB.Storage.PropertyKeyCodec
    def format_id do
      <<"catch-up-property-v1">>
    end

    @impl PositionDB.Storage.PropertyKeyCodec
    def encode(
          :color,
          :white
        ) do
      {:ok, <<1, 1>>}
    end

    def encode(
          :color,
          :black
        ) do
      {:ok, <<1, 2>>}
    end

    def encode(
          :selected,
          true
        ) do
      {:ok, <<2, 1>>}
    end

    def encode(
          :selected,
          false
        ) do
      {:ok, <<2, 0>>}
    end

    def encode(
          _name,
          _value
        ) do
      {:error, :unsupported_property}
    end
  end

  defmodule TrackingStorage do
    def get(
          storage,
          position_id
        ) do
      send(
        storage.test_pid,
        {:get, position_id}
      )

      case Map.fetch(
             storage.positions,
             position_id
           ) do
        {:ok, position} ->
          {:ok, position}

        :error ->
          :not_found
      end
    end

    def cardinality(storage) do
      map_size(storage.positions)
    end
  end

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "position-db-property-index-catch-up-#{System.unique_integer([:positive])}"
      )

    directory =
      Path.join(
        root,
        "index"
      )

    File.mkdir_p!(root)

    on_exit(fn ->
      File.rm_rf!(root)
    end)

    %{
      directory: directory
    }
  end

  test "starts at the first position after the durable watermark and recovers its postings",
       %{
         directory: directory
       } do
    positions = %{
      1 => %{
        color: :black,
        selected: false
      },
      2 => %{
        color: :white,
        selected: true
      },
      3 => %{
        color: :white,
        selected: false
      }
    }

    store =
      position_store(positions)

    assert {:ok, disk_index} =
             Disk.create(
               directory,
               codec: TestCodec,
               bucket_count: 1
             )

    assert {:ok, disk_index} =
             Disk.add(
               disk_index,
               {:color, :black},
               1
             )

    assert {:ok, disk_index} =
             Disk.add(
               disk_index,
               {:selected, false},
               1
             )

    assert {:ok, disk_index} =
             Disk.advance(
               disk_index,
               1
             )

    indexer =
      position_indexer(disk_index)

    assert {:ok, color_key} =
             TestCodec.encode(
               :color,
               :white
             )

    assert {:ok, selected_key} =
             TestCodec.encode(
               :selected,
               true
             )

    color_entry =
      Entry.encode(
        color_key,
        2
      )

    selected_entry =
      Entry.encode(
        selected_key,
        2
      )

    path =
      Layout.bucket_path(
        directory,
        0
      )

    existing =
      File.read!(path)

    File.write!(
      path,
      <<
        existing::binary,
        color_entry::binary,
        binary_part(
          selected_entry,
          0,
          5
        )::binary
      >>
    )

    assert {:ok, indexer} =
             CatchUp.run(
               store,
               indexer
             )

    assert_receive {:get, 2}
    assert_receive {:get, 3}
    refute_receive {:get, 1}

    disk_index =
      indexer.index.backend

    assert Disk.indexed_through(disk_index) ==
             3

    assert Disk.lookup(
             disk_index,
             {:color, :white}
           ) ==
             {:ok, [2, 3]}

    assert Disk.lookup(
             disk_index,
             {:selected, true}
           ) ==
             {:ok, [2]}

    assert Disk.lookup(
             disk_index,
             {:selected, false}
           ) ==
             {:ok, [1, 3]}

    assert File.read!(path) ==
             <<
               existing::binary,
               color_entry::binary,
               selected_entry::binary,
               Entry.encode(
                 elem(
                   TestCodec.encode(
                     :color,
                     :white
                   ),
                   1
                 ),
                 3
               )::binary,
               Entry.encode(
                 elem(
                   TestCodec.encode(
                     :selected,
                     false
                   ),
                   1
                 ),
                 3
               )::binary
             >>
  end

  test "does not advance past a position whose postings fail",
       %{
         directory: directory
       } do
    positions = %{
      1 => %{
        color: :black,
        selected: false
      },
      2 => %{
        color: :white,
        selected: true
      },
      3 => %{
        color: :unsupported,
        selected: false
      }
    }

    store =
      position_store(positions)

    assert {:ok, disk_index} =
             Disk.create(
               directory,
               codec: TestCodec,
               bucket_count: 1
             )

    assert {:ok, disk_index} =
             Disk.add(
               disk_index,
               {:color, :black},
               1
             )

    assert {:ok, disk_index} =
             Disk.add(
               disk_index,
               {:selected, false},
               1
             )

    assert {:ok, disk_index} =
             Disk.advance(
               disk_index,
               1
             )

    indexer =
      position_indexer(disk_index)

    assert CatchUp.run(
             store,
             indexer
           ) ==
             {:error, :unsupported_property}

    assert IndexProgressStore.read(directory) ==
             {:ok, 2}

    assert {:ok, reopened} =
             Disk.open(
               directory,
               codec: TestCodec
             )

    assert Disk.lookup(
             reopened,
             {:color, :white}
           ) ==
             {:ok, [2]}

    assert Disk.lookup(
             reopened,
             {:selected, true}
           ) ==
             {:ok, [2]}
  end

  test "does no position reads when the property index is already caught up",
       %{
         directory: directory
       } do
    positions = %{
      1 => %{
        color: :black,
        selected: false
      }
    }

    store =
      position_store(positions)

    assert {:ok, disk_index} =
             Disk.create(
               directory,
               codec: TestCodec,
               bucket_count: 1
             )

    assert {:ok, disk_index} =
             Disk.advance(
               disk_index,
               1
             )

    indexer =
      position_indexer(disk_index)

    assert {:ok, caught_up} =
             CatchUp.run(
               store,
               indexer
             )

    assert Disk.indexed_through(caught_up.index.backend) ==
             1

    refute_receive {:get, _position_id}
  end

  defp position_store(positions) do
    PositionStore.new(
      & &1,
      TrackingStorage,
      %{
        positions: positions,
        test_pid: self()
      }
    )
  end

  defp position_indexer(disk_index) do
    property_index =
      PropertyIndex.new(
        Disk,
        disk_index
      )

    PositionIndexer.new(
      [
        {:color, & &1.color},
        {:selected, & &1.selected}
      ],
      property_index
    )
  end
end
