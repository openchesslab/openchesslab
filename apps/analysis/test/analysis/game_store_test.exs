defmodule Analysis.GameStoreTest do
  use ExUnit.Case, async: false

  alias Analysis.Game
  alias Analysis.GameStore

  defmodule RecordingAdapter do
    @behaviour Analysis.GameStore

    def insert(store, game) do
      send(self(), {:insert, store, game})
      {:ok, 1}
    end

    def get(store, game_id) do
      send(self(), {:get, store, game_id})
      :not_found
    end

    def list(store) do
      send(self(), {:list, store})
      []
    end

    def update(store, game, revision) do
      send(self(), {:update, store, game, revision})
      {:ok, revision + 1}
    end

    def delete(store, game_id, revision) do
      send(self(), {:delete, store, game_id, revision})
      :ok
    end
  end

  setup do
    previous =
      Application.get_env(
        :analysis,
        GameStore,
        :not_configured
      )

    on_exit(fn ->
      case previous do
        :not_configured ->
          Application.delete_env(
            :analysis,
            GameStore
          )

        value ->
          Application.put_env(
            :analysis,
            GameStore,
            value
          )
      end
    end)

    :ok
  end

  test "uses the cluster-wide store by default" do
    Application.put_env(
      :analysis,
      GameStore,
      adapter: RecordingAdapter
    )

    game =
      Game.new(
        "game-1",
        42
      )

    assert {:ok, 1} =
             GameStore.insert(game)

    assert_received {
      :insert,
      store,
      ^game
    }

    assert store == GameStore.clustered_store()
  end
end
