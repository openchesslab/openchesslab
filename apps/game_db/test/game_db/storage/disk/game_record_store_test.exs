defmodule GameDB.Storage.Disk.GameRecordStoreTest do
  use ExUnit.Case, async: true

  alias GameDB.Storage.Disk.GameRecordStore
  alias GameDB.Storage.Disk.RecordStore

  defmodule TestCodec do
    @behaviour GameDB.RecordCodec

    @impl true
    def encode({:game, value})
        when is_integer(value) and
               value >= 0 do
      {:ok,
       <<
         value::unsigned-big-64
       >>}
    end

    def encode(_record) do
      {:error, :invalid_game}
    end

    @impl true
    def decode(<<
          value::unsigned-big-64
        >>) do
      {:ok, {:game, value}}
    end

    def decode(_encoded) do
      {:error, :invalid_game_record}
    end
  end

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "game-db-game-record-store-#{System.unique_integer([:positive])}"
      )

    on_exit(fn ->
      File.rm_rf!(directory)
    end)

    assert {:ok, record_store} =
             RecordStore.create(directory)

    store =
      GameRecordStore.new(
        record_store,
        TestCodec
      )

    %{
      directory: directory,
      record_store: record_store,
      store: store
    }
  end

  test "encodes, stores and decodes canonical game records", %{
    store: store
  } do
    assert {:ok, 1} =
             GameRecordStore.append(
               store,
               {:game, 42}
             )

    assert {:ok, 2} =
             GameRecordStore.append(
               store,
               {:game, 99}
             )

    assert GameRecordStore.get(
             store,
             1
           ) ==
             {:ok, {:game, 42}}

    assert GameRecordStore.get(
             store,
             2
           ) ==
             {:ok, {:game, 99}}
  end

  test "returns not_found for an unknown game id", %{
    store: store
  } do
    assert GameRecordStore.get(
             store,
             1
           ) ==
             :not_found
  end

  test "does not append a record rejected by the codec", %{
    store: store
  } do
    assert GameRecordStore.append(
             store,
             :invalid
           ) ==
             {:error, :invalid_game}

    assert GameRecordStore.cardinality(store) ==
             {:ok, 0}
  end

  test "reports an invalid persisted record", %{
    record_store: record_store,
    store: store
  } do
    assert {:ok, 1} =
             RecordStore.append(
               record_store,
               <<"broken">>
             )

    assert GameRecordStore.get(
             store,
             1
           ) ==
             {:error, :invalid_game_record}
  end

  test "reports the number of stored games", %{
    store: store
  } do
    assert GameRecordStore.cardinality(store) ==
             {:ok, 0}

    assert {:ok, 1} =
             GameRecordStore.append(
               store,
               {:game, 1}
             )

    assert GameRecordStore.cardinality(store) ==
             {:ok, 1}
  end
end
