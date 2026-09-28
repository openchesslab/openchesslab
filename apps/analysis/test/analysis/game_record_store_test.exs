defmodule Analysis.GameRecordStoreTest do
  use ExUnit.Case, async: false

  alias Analysis.GameRecord
  alias Analysis.GameRecordStore

  defmodule RecordingAdapter do
    @behaviour Analysis.GameRecordStore

    def insert(
          store,
          record
        ) do
      send(
        self(),
        {:insert, store, record}
      )

      :ok
    end

    def get(
          store,
          record_id
        ) do
      send(
        self(),
        {:get, store, record_id}
      )

      :not_found
    end

    def list(store) do
      send(
        self(),
        {:list, store}
      )

      []
    end
  end

  setup do
    previous =
      Application.get_env(
        :analysis,
        GameRecordStore,
        :not_configured
      )

    on_exit(fn ->
      case previous do
        :not_configured ->
          Application.delete_env(
            :analysis,
            GameRecordStore
          )

        value ->
          Application.put_env(
            :analysis,
            GameRecordStore,
            value
          )
      end
    end)

    :ok
  end

  test "uses the cluster-wide store by default" do
    Application.put_env(
      :analysis,
      GameRecordStore,
      adapter: RecordingAdapter
    )

    record =
      GameRecord.new(
        "record-1",
        42
      )

    assert :ok =
             GameRecordStore.insert(record)

    assert_received {
      :insert,
      store,
      ^record
    }

    assert store ==
             GameRecordStore.clustered_store()
  end

  test "delegates get to the configured adapter" do
    Application.put_env(
      :analysis,
      GameRecordStore,
      adapter: RecordingAdapter,
      store: :configured_store
    )

    assert GameRecordStore.get("record-1") ==
             :not_found

    assert_received {
      :get,
      :configured_store,
      "record-1"
    }
  end

  test "delegates list to the configured adapter" do
    Application.put_env(
      :analysis,
      GameRecordStore,
      adapter: RecordingAdapter,
      store: :configured_store
    )

    assert GameRecordStore.list() == []

    assert_received {
      :list,
      :configured_store
    }
  end

  test "reports ready when the game record store is reachable" do
    Application.delete_env(
      :analysis,
      GameRecordStore
    )

    assert GameRecordStore.ready?()
  end

  test "reports not ready when the configured store is unavailable" do
    Application.put_env(
      :analysis,
      GameRecordStore,
      store: :unavailable_game_record_store
    )

    refute GameRecordStore.ready?()
  end
end
