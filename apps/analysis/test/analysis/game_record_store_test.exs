defmodule Analysis.GameRecordStoreTest do
  use ExUnit.Case, async: false

  alias Analysis.GameRecord
  alias Analysis.GameRecordStore

  defmodule RecordingRepository do
    @moduledoc false

    @behaviour Analysis.GameRecordRepository

    @impl true
    def ready? do
      notify(:ready)
      true
    end

    @impl true
    def insert(record) do
      notify({:insert, record})
      :ok
    end

    @impl true
    def get(record_id) do
      notify({:get, record_id})
      :not_found
    end

    @impl true
    def records_page_by_game_id(game_id, page_size) do
      notify({
        :records_page_by_game_id,
        game_id,
        page_size
      })

      {:ok, [], :record_cursor}
    end

    @impl true
    def next_records_page(cursor, page_size) do
      notify({
        :next_records_page,
        cursor,
        page_size
      })

      {:ok, [], :done}
    end

    @impl true
    def close_records(cursor) do
      notify({:close_records, cursor})
      :ok
    end

    defp notify(message) do
      send(
        self(),
        {
          :game_record_repository,
          message
        }
      )
    end
  end

  setup do
    previous =
      Application.get_env(
        :analysis,
        :game_record_repository,
        :not_configured
      )

    Application.put_env(
      :analysis,
      :game_record_repository,
      RecordingRepository
    )

    on_exit(fn ->
      restore_repository(previous)
    end)

    :ok
  end

  test "reports repository readiness" do
    assert GameRecordStore.ready?()

    assert_receive {
      :game_record_repository,
      :ready
    }
  end

  test "inserts through the configured repository" do
    record =
      GameRecord.new(
        "record-1",
        42
      )

    assert :ok =
             GameRecordStore.insert(record)

    assert_receive {
      :game_record_repository,
      {
        :insert,
        ^record
      }
    }
  end

  test "gets through the configured repository" do
    assert GameRecordStore.get("record-1") ==
             :not_found

    assert_receive {
      :game_record_repository,
      {
        :get,
        "record-1"
      }
    }
  end

  test "pages records through the configured repository" do
    assert GameRecordStore.records_page_by_game_id(
             42,
             25
           ) ==
             {:ok, [], :record_cursor}

    assert_receive {
      :game_record_repository,
      {
        :records_page_by_game_id,
        42,
        25
      }
    }

    assert GameRecordStore.next_records_page(
             :record_cursor,
             25
           ) ==
             {:ok, [], :done}

    assert_receive {
      :game_record_repository,
      {
        :next_records_page,
        :record_cursor,
        25
      }
    }
  end

  test "closes record scans through the configured repository" do
    assert :ok =
             GameRecordStore.close_record_scan(:record_cursor)

    assert_receive {
      :game_record_repository,
      {
        :close_records,
        :record_cursor
      }
    }
  end

  test "defaults to the PostgreSQL repository" do
    Application.delete_env(
      :analysis,
      :game_record_repository
    )

    assert GameRecordStore.repository() ==
             Analysis.GameRecordRepository.Postgres
  end

  defp restore_repository(:not_configured) do
    Application.delete_env(
      :analysis,
      :game_record_repository
    )
  end

  defp restore_repository(repository) do
    Application.put_env(
      :analysis,
      :game_record_repository,
      repository
    )
  end
end
