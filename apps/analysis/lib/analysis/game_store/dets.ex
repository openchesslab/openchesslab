defmodule Analysis.GameStore.Dets do
  @moduledoc false

  use GenServer

  @behaviour Analysis.GameStore

  alias Analysis.Game

  @table __MODULE__

  @type revision :: pos_integer()
  @type store :: GenServer.server()

  @spec start_link(Path.t()) :: GenServer.on_start()
  def start_link(path) do
    GenServer.start_link(__MODULE__, path)
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
  @spec list(store()) :: [{Game.t(), revision()}]
  def list(store) do
    GenServer.call(store, :list)
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
  def init(path) do
    options = [
      file: String.to_charlist(path),
      type: :set,
      keypos: 1
    ]

    case :dets.open_file(@table, options) do
      {:ok, @table} ->
        {:ok, @table}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(
        {:insert, %Game{id: id} = game},
        _from,
        table
      ) do
    case :dets.insert_new(table, {id, 1, game}) do
      true ->
        :ok = :dets.sync(table)
        {:reply, {:ok, 1}, table}

      false ->
        {:reply, {:error, :already_exists}, table}
    end
  end

  def handle_call({:get, game_id}, _from, table) do
    reply =
      case :dets.lookup(table, game_id) do
        [{^game_id, revision, game}] ->
          {:ok, game, revision}

        [] ->
          :not_found
      end

    {:reply, reply, table}
  end

  def handle_call(:list, _from, table) do
    games =
      :dets.foldl(
        fn {_id, revision, game}, acc ->
          [{game, revision} | acc]
        end,
        [],
        table
      )

    {:reply, games, table}
  end

  def handle_call(
        {:update, %Game{id: id} = game, expected_revision},
        _from,
        table
      ) do
    case :dets.lookup(table, id) do
      [] ->
        {:reply, {:error, :not_found}, table}

      [{^id, revision, _stored_game}]
      when revision != expected_revision ->
        {:reply, {:error, :conflict}, table}

      [{^id, revision, _stored_game}] ->
        new_revision = revision + 1

        :ok =
          :dets.insert(
            table,
            {id, new_revision, game}
          )

        :ok = :dets.sync(table)

        {:reply, {:ok, new_revision}, table}
    end
  end

  def handle_call(
        {:delete, game_id, expected_revision},
        _from,
        table
      ) do
    case :dets.lookup(table, game_id) do
      [] ->
        {:reply, {:error, :not_found}, table}

      [{^game_id, revision, _game}]
      when revision != expected_revision ->
        {:reply, {:error, :conflict}, table}

      [{^game_id, _revision, _game}] ->
        :ok = :dets.delete(table, game_id)
        :ok = :dets.sync(table)

        {:reply, :ok, table}
    end
  end

  @impl true
  def terminate(_reason, table) do
    :dets.close(table)
    :ok
  end
end
