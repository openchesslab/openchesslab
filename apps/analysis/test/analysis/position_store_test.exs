defmodule Analysis.PositionStoreTest do
  use ExUnit.Case, async: false

  alias Analysis.PositionQuery, as: Query
  alias Analysis.PositionStore
  alias Chess.Position

  defmodule RecordingRepository do
    @moduledoc false

    @behaviour Analysis.PositionRepository

    alias Chess.Position

    @impl true
    def ready? do
      notify(:ready)
      true
    end

    @impl true
    def put(position) do
      notify({:put, position})
      {:ok, 42}
    end

    @impl true
    def get(position_id) do
      notify({:get, position_id})
      {:ok, Position.starting_position()}
    end

    @impl true
    def find(position) do
      notify({:find, position})
      {:ok, 42}
    end

    @impl true
    def query_page(query, page_size) do
      notify({:query_page, query, page_size})
      {:ok, [1], :position_cursor}
    end

    @impl true
    def next_query_page(cursor, page_size) do
      notify({:next_query_page, cursor, page_size})
      {:ok, [2], :done}
    end

    @impl true
    def close_query(cursor) do
      notify({:close_query, cursor})
      :ok
    end

    defp notify(message) do
      send(
        self(),
        {
          :position_repository,
          message
        }
      )
    end
  end

  setup do
    previous =
      Application.get_env(
        :analysis,
        :position_repository,
        :not_configured
      )

    Application.put_env(
      :analysis,
      :position_repository,
      RecordingRepository
    )

    on_exit(fn ->
      restore_repository(previous)
    end)

    :ok
  end

  test "reports repository readiness" do
    assert PositionStore.ready?()
    assert_receive {:position_repository, :ready}
  end

  test "appends through the configured repository" do
    position =
      Position.starting_position()

    assert PositionStore.append(position) == 42

    assert_receive {
      :position_repository,
      {
        :put,
        ^position
      }
    }
  end

  test "gets through the configured repository" do
    assert PositionStore.get(123) ==
             {:ok, Position.starting_position()}

    assert_receive {
      :position_repository,
      {
        :get,
        123
      }
    }
  end

  test "finds through the configured repository" do
    position =
      Position.starting_position()

    assert PositionStore.find(position) ==
             {:ok, 42}

    assert_receive {
      :position_repository,
      {
        :find,
        ^position
      }
    }
  end

  test "pages queries through the configured repository" do
    query =
      Query.match_all()

    assert PositionStore.query_page(
             query,
             10
           ) ==
             {
               :ok,
               [1],
               :position_cursor
             }

    assert_receive {
      :position_repository,
      {
        :query_page,
        ^query,
        10
      }
    }

    assert PositionStore.next_query_page(
             :position_cursor,
             10
           ) ==
             {
               :ok,
               [2],
               :done
             }

    assert_receive {
      :position_repository,
      {
        :next_query_page,
        :position_cursor,
        10
      }
    }

    assert :ok =
             PositionStore.close_query(:position_cursor)

    assert_receive {
      :position_repository,
      {
        :close_query,
        :position_cursor
      }
    }
  end

  defp restore_repository(:not_configured) do
    Application.delete_env(
      :analysis,
      :position_repository
    )
  end

  defp restore_repository(repository) do
    Application.put_env(
      :analysis,
      :position_repository,
      repository
    )
  end
end
