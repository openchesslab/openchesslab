defmodule Analysis.GameStore.Memory do
  @moduledoc false

  alias Analysis.Game

  @type revision :: pos_integer()

  @type entry :: %{
          game: Game.t(),
          revision: revision()
        }

  @type t :: %__MODULE__{
          games: %{optional(Game.id()) => entry()}
        }

  defstruct games: %{}

  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @spec insert(t(), Game.t()) ::
          {:ok, t(), revision()}
          | {:error, :already_exists}
  def insert(%__MODULE__{} = store, %Game{id: id} = game) do
    if Map.has_key?(store.games, id) do
      {:error, :already_exists}
    else
      revision = 1
      entry = %{game: game, revision: revision}

      {:ok, %{store | games: Map.put(store.games, id, entry)}, revision}
    end
  end

  @spec get(t(), Game.id()) ::
          {:ok, Game.t(), revision()}
          | :not_found
  def get(%__MODULE__{} = store, game_id) do
    case Map.fetch(store.games, game_id) do
      {:ok, %{game: game, revision: revision}} ->
        {:ok, game, revision}

      :error ->
        :not_found
    end
  end

  @spec update(t(), Game.t(), revision()) ::
          {:ok, t(), revision()}
          | {:error, :not_found | :conflict}
  def update(
        %__MODULE__{} = store,
        %Game{id: id} = game,
        expected_revision
      ) do
    case Map.fetch(store.games, id) do
      :error ->
        {:error, :not_found}

      {:ok, %{revision: revision}}
      when revision != expected_revision ->
        {:error, :conflict}

      {:ok, %{revision: revision}} ->
        new_revision = revision + 1
        entry = %{game: game, revision: new_revision}

        {:ok, %{store | games: Map.put(store.games, id, entry)}, new_revision}
    end
  end

  @spec delete(t(), Game.id(), revision()) ::
          {:ok, t()}
          | {:error, :not_found | :conflict}
  def delete(
        %__MODULE__{} = store,
        game_id,
        expected_revision
      ) do
    case Map.fetch(store.games, game_id) do
      :error ->
        {:error, :not_found}

      {:ok, %{revision: revision}}
      when revision != expected_revision ->
        {:error, :conflict}

      {:ok, _entry} ->
        {:ok, %{store | games: Map.delete(store.games, game_id)}}
    end
  end
end
