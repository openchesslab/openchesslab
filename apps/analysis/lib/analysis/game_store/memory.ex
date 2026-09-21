defmodule Analysis.GameStore.Memory do
  @moduledoc false

  use GenServer

  @behaviour Analysis.GameStore

  alias Analysis.Game

  @type revision :: pos_integer()
  @type store :: GenServer.server()

  @type entry :: %{
          game: Game.t(),
          revision: revision()
        }

  @spec start_link() :: GenServer.on_start()
  def start_link do
    GenServer.start_link(__MODULE__, %{})
  end

  @impl Analysis.GameStore
  @spec insert(store(), Game.t()) ::
          {:ok, revision()}
          | {:error, :already_exists}
  def insert(store, %Game{} = game) do
    GenServer.call(store, {:insert, game})
  end

  @impl Analysis.GameStore
  @spec get(store(), Game.id()) ::
          {:ok, Game.t(), revision()}
          | :not_found
  def get(store, game_id) do
    GenServer.call(store, {:get, game_id})
  end

  @impl Analysis.GameStore
  @spec update(store(), Game.t(), revision()) ::
          {:ok, revision()}
          | {:error, :not_found | :conflict}
  def update(store, %Game{} = game, expected_revision) do
    GenServer.call(
      store,
      {:update, game, expected_revision}
    )
  end

  @impl Analysis.GameStore
  @spec delete(store(), Game.id(), revision()) ::
          :ok
          | {:error, :not_found | :conflict}
  def delete(store, game_id, expected_revision) do
    GenServer.call(
      store,
      {:delete, game_id, expected_revision}
    )
  end

  @impl true
  def init(games) do
    {:ok, games}
  end

  @impl true
  def handle_call(
        {:insert, %Game{id: id} = game},
        _from,
        games
      ) do
    if Map.has_key?(games, id) do
      {:reply, {:error, :already_exists}, games}
    else
      revision = 1
      entry = %{game: game, revision: revision}

      {:reply, {:ok, revision}, Map.put(games, id, entry)}
    end
  end

  def handle_call({:get, game_id}, _from, games) do
    reply =
      case Map.fetch(games, game_id) do
        {:ok, %{game: game, revision: revision}} ->
          {:ok, game, revision}

        :error ->
          :not_found
      end

    {:reply, reply, games}
  end

  def handle_call(
        {:update, %Game{id: id} = game, expected_revision},
        _from,
        games
      ) do
    case Map.fetch(games, id) do
      :error ->
        {:reply, {:error, :not_found}, games}

      {:ok, %{revision: revision}}
      when revision != expected_revision ->
        {:reply, {:error, :conflict}, games}

      {:ok, %{revision: revision}} ->
        new_revision = revision + 1

        entry = %{
          game: game,
          revision: new_revision
        }

        {:reply, {:ok, new_revision}, Map.put(games, id, entry)}
    end
  end

  def handle_call(
        {:delete, game_id, expected_revision},
        _from,
        games
      ) do
    case Map.fetch(games, game_id) do
      :error ->
        {:reply, {:error, :not_found}, games}

      {:ok, %{revision: revision}}
      when revision != expected_revision ->
        {:reply, {:error, :conflict}, games}

      {:ok, _entry} ->
        {:reply, :ok, Map.delete(games, game_id)}
    end
  end
end
