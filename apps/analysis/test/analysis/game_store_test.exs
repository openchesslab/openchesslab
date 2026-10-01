defmodule Analysis.GameStoreTest do
  use ExUnit.Case, async: false

  alias Analysis.GameContent
  alias Analysis.GameOccurrence
  alias Analysis.GameStore

  defmodule RecordingRepository do
    @moduledoc false

    @behaviour Analysis.GameRepository

    alias Analysis.GameContent
    alias Analysis.GameOccurrence

    @impl true
    def ready? do
      notify(:ready)
      true
    end

    @impl true
    def put(fingerprint, content, position_ids) do
      notify({:put, fingerprint, content, position_ids})
      {:ok, 42}
    end

    @impl true
    def find(fingerprint, content) do
      notify({:find, fingerprint, content})
      {:ok, 42}
    end

    @impl true
    def get(game_id) do
      notify({:get, game_id})
      {:ok, GameContent.new(10)}
    end

    @impl true
    def occurrences(game_id) do
      notify({:occurrences, game_id})

      {:ok,
       [
         GameOccurrence.new(
           7,
           game_id,
           0,
           10
         )
       ]}
    end

    @impl true
    def occurrences_page(position_id, page_size) do
      notify({:occurrences_page, position_id, page_size})

      {:ok,
       [
         GameOccurrence.new(
           7,
           42,
           0,
           position_id
         )
       ], :occurrence_cursor}
    end

    @impl true
    def next_occurrences_page(cursor, page_size) do
      notify({:next_occurrences_page, cursor, page_size})
      {:ok, [], :done}
    end

    @impl true
    def close_occurrences(cursor) do
      notify({:close_occurrences, cursor})
      :ok
    end

    @impl true
    def get_occurrence(occurrence_id) do
      notify({:get_occurrence, occurrence_id})

      {:ok,
       GameOccurrence.new(
         occurrence_id,
         42,
         0,
         10
       )}
    end

    defp notify(message) do
      send(
        self(),
        {
          :game_repository,
          message
        }
      )
    end
  end

  defmodule InvalidOccurrencesRepository do
    @moduledoc false

    @behaviour Analysis.GameRepository

    alias Analysis.GameContent

    @impl true
    def ready?, do: true

    @impl true
    def put(_fingerprint, _content, _position_ids), do: {:error, :unsupported}

    @impl true
    def find(_fingerprint, _content), do: :not_found

    @impl true
    def get(_game_id), do: {:ok, GameContent.new(10)}

    @impl true
    def occurrences(_game_id), do: {:ok, []}

    @impl true
    def occurrences_page(_position_id, _page_size), do: {:ok, [], :done}

    @impl true
    def next_occurrences_page(_cursor, _page_size), do: {:ok, [], :done}

    @impl true
    def close_occurrences(_cursor), do: :ok

    @impl true
    def get_occurrence(_occurrence_id), do: :not_found
  end

  setup do
    previous =
      Application.get_env(
        :analysis,
        :game_repository,
        :not_configured
      )

    Application.put_env(
      :analysis,
      :game_repository,
      RecordingRepository
    )

    on_exit(fn ->
      restore_repository(previous)
    end)

    :ok
  end

  test "reports repository readiness" do
    assert GameStore.ready?()
    assert_receive {:game_repository, :ready}
  end

  test "stores through the configured repository" do
    content =
      GameContent.new(10)

    fingerprint =
      :binary.copy(<<1>>, 32)

    assert GameStore.put(
             fingerprint,
             content,
             [10]
           ) ==
             {:ok, 42}

    assert_receive {
      :game_repository,
      {
        :put,
        ^fingerprint,
        ^content,
        [10]
      }
    }
  end

  test "finds through the configured repository" do
    content =
      GameContent.new(10)

    fingerprint =
      :binary.copy(<<2>>, 32)

    assert GameStore.find(
             fingerprint,
             content
           ) ==
             {:ok, 42}

    assert_receive {
      :game_repository,
      {
        :find,
        ^fingerprint,
        ^content
      }
    }
  end

  test "gets through the configured repository" do
    assert GameStore.get(42) ==
             {:ok, GameContent.new(10)}

    assert_receive {
      :game_repository,
      {
        :get,
        42
      }
    }
  end

  test "loads canonical content with validated occurrences" do
    assert {
             :ok,
             %GameContent{initial_position_id: 10},
             [
               %GameOccurrence{
                 id: 7,
                 game_id: 42,
                 ply: 0,
                 position_id: 10
               }
             ]
           } =
             GameStore.load(42)

    assert_receive {:game_repository, {:get, 42}}
    assert_receive {:game_repository, {:occurrences, 42}}
  end

  test "rejects inconsistent persisted occurrences" do
    Application.put_env(
      :analysis,
      :game_repository,
      InvalidOccurrencesRepository
    )

    assert GameStore.load(42) ==
             {:error, :invalid_occurrences}
  end

  test "pages occurrences through the configured repository" do
    assert {
             :ok,
             [
               %GameOccurrence{
                 id: 7,
                 game_id: 42,
                 ply: 0,
                 position_id: 10
               }
             ],
             :occurrence_cursor
           } =
             GameStore.occurrences_page(
               10,
               25
             )

    assert_receive {
      :game_repository,
      {
        :occurrences_page,
        10,
        25
      }
    }

    assert GameStore.next_occurrences_page(
             :occurrence_cursor,
             25
           ) ==
             {:ok, [], :done}

    assert_receive {
      :game_repository,
      {
        :next_occurrences_page,
        :occurrence_cursor,
        25
      }
    }
  end

  test "closes occurrence scans through the configured repository" do
    assert :ok =
             GameStore.close_occurrence_scan(:occurrence_cursor)

    assert_receive {
      :game_repository,
      {
        :close_occurrences,
        :occurrence_cursor
      }
    }
  end

  test "gets an occurrence through the configured repository" do
    assert GameStore.get_occurrence(7) ==
             {:ok,
              GameOccurrence.new(
                7,
                42,
                0,
                10
              )}

    assert_receive {
      :game_repository,
      {
        :get_occurrence,
        7
      }
    }
  end

  test "defaults to the PostgreSQL repository" do
    Application.delete_env(
      :analysis,
      :game_repository
    )

    assert GameStore.repository() ==
             Analysis.GameRepository.Postgres
  end

  defp restore_repository(:not_configured) do
    Application.delete_env(
      :analysis,
      :game_repository
    )
  end

  defp restore_repository(repository) do
    Application.put_env(
      :analysis,
      :game_repository,
      repository
    )
  end
end
