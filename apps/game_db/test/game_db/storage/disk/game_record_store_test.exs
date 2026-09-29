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

  test "stores and decodes canonical game records with their fingerprints", %{
    store: store
  } do
    first_fingerprint =
      fingerprint(1)

    second_fingerprint =
      fingerprint(2)

    assert {:ok, 1} =
             GameRecordStore.append(
               store,
               first_fingerprint,
               {:game, 42}
             )

    assert {:ok, 2} =
             GameRecordStore.append(
               store,
               second_fingerprint,
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

    assert GameRecordStore.fingerprint(
             store,
             1
           ) ==
             {:ok, first_fingerprint}

    assert GameRecordStore.fingerprint(
             store,
             2
           ) ==
             {:ok, second_fingerprint}
  end

  test "persists the fingerprint with the game record", %{
    directory: directory,
    store: store
  } do
    fingerprint =
      fingerprint(42)

    assert {:ok, 1} =
             GameRecordStore.append(
               store,
               fingerprint,
               {:game, 123}
             )

    assert {:ok, reopened_record_store} =
             RecordStore.open(directory)

    reopened =
      GameRecordStore.new(
        reopened_record_store,
        TestCodec
      )

    assert GameRecordStore.get(
             reopened,
             1
           ) ==
             {:ok, {:game, 123}}

    assert GameRecordStore.fingerprint(
             reopened,
             1
           ) ==
             {:ok, fingerprint}
  end

  test "returns not_found for an unknown game id", %{
    store: store
  } do
    assert GameRecordStore.get(
             store,
             1
           ) ==
             :not_found

    assert GameRecordStore.fingerprint(
             store,
             1
           ) ==
             :not_found
  end

  test "rejects fingerprints with the wrong size", %{
    store: store
  } do
    assert GameRecordStore.append(
             store,
             <<"too-short">>,
             {:game, 42}
           ) ==
             {:error, :invalid_fingerprint_size}

    assert GameRecordStore.cardinality(store) ==
             {:ok, 0}
  end

  test "does not append a record rejected by the codec", %{
    store: store
  } do
    assert GameRecordStore.append(
             store,
             fingerprint(1),
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

    assert GameRecordStore.fingerprint(
             store,
             1
           ) ==
             {:error, :invalid_game_record}
  end

  test "reports an invalid encoded canonical game", %{
    record_store: record_store,
    store: store
  } do
    assert {:ok, 1} =
             RecordStore.append(
               record_store,
               <<
                 fingerprint(1)::binary,
                 "broken"::binary
               >>
             )

    assert GameRecordStore.fingerprint(
             store,
             1
           ) ==
             {:ok, fingerprint(1)}

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
               fingerprint(1),
               {:game, 1}
             )

    assert GameRecordStore.cardinality(store) ==
             {:ok, 1}
  end

  defp fingerprint(prefix) do
    <<
      prefix::unsigned-big-32,
      0::size(224)
    >>
  end
end
