defmodule Analysis.GameRecordStore.Memory do
  @moduledoc """
  In-memory reference implementation of GameRecordStore.
  """

  use GenServer

  @behaviour Analysis.GameRecordStore

  alias Analysis.GameRecord

  @type store :: GenServer.server()

  @type t :: %__MODULE__{
          records: %{
            GameRecord.id() => GameRecord.t()
          },
          record_ids_by_game: %{
            GameDB.game_id() => MapSet.t(GameRecord.id())
          }
        }

  defstruct records: %{},
            record_ids_by_game: %{}

  @spec start_link(keyword()) ::
          GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(
      __MODULE__,
      %__MODULE__{},
      Keyword.take(
        opts,
        [:name]
      )
    )
  end

  @spec child_spec(keyword()) ::
          Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id:
        Keyword.get(
          opts,
          :name,
          __MODULE__
        ),
      start: {
        __MODULE__,
        :start_link,
        [opts]
      }
    }
  end

  @impl Analysis.GameRecordStore
  @spec insert(
          store(),
          GameRecord.t()
        ) ::
          :ok
          | {:error, :already_exists}
  def insert(
        store,
        %GameRecord{} = record
      ) do
    GenServer.call(
      store,
      {:insert, record}
    )
  end

  @impl Analysis.GameRecordStore
  @spec get(
          store(),
          GameRecord.id()
        ) ::
          {:ok, GameRecord.t()}
          | :not_found
  def get(
        store,
        record_id
      ) do
    GenServer.call(
      store,
      {:get, record_id}
    )
  end

  @impl Analysis.GameRecordStore
  @spec list(store()) ::
          [GameRecord.t()]
  def list(store) do
    GenServer.call(
      store,
      :list
    )
  end

  @impl Analysis.GameRecordStore
  @spec list_by_game_id(
          store(),
          GameDB.game_id()
        ) ::
          [GameRecord.t()]
  def list_by_game_id(
        store,
        game_id
      ) do
    GenServer.call(
      store,
      {:list_by_game_id, game_id}
    )
  end

  @impl true
  def init(%__MODULE__{} = state) do
    {:ok, state}
  end

  @impl true
  def handle_call(
        :ping,
        _from,
        state
      ) do
    {
      :reply,
      :ok,
      state
    }
  end

  def handle_call(
        {:insert, %GameRecord{id: id} = record},
        _from,
        state
      ) do
    if Map.has_key?(
         state.records,
         id
       ) do
      {
        :reply,
        {:error, :already_exists},
        state
      }
    else
      game_id =
        GameRecord.game_id(record)

      updated_state = %{
        state
        | records:
            Map.put(
              state.records,
              id,
              record
            ),
          record_ids_by_game:
            Map.update(
              state.record_ids_by_game,
              game_id,
              MapSet.new([id]),
              &MapSet.put(&1, id)
            )
      }

      {
        :reply,
        :ok,
        updated_state
      }
    end
  end

  def handle_call(
        {:get, record_id},
        _from,
        state
      ) do
    reply =
      case Map.fetch(
             state.records,
             record_id
           ) do
        {:ok, record} ->
          {:ok, record}

        :error ->
          :not_found
      end

    {
      :reply,
      reply,
      state
    }
  end

  def handle_call(
        :list,
        _from,
        state
      ) do
    {
      :reply,
      Map.values(state.records),
      state
    }
  end

  def handle_call(
        {:list_by_game_id, game_id},
        _from,
        state
      ) do
    records =
      state.record_ids_by_game
      |> Map.get(
        game_id,
        MapSet.new()
      )
      |> Enum.map(
        &Map.fetch!(
          state.records,
          &1
        )
      )

    {
      :reply,
      records,
      state
    }
  end
end
