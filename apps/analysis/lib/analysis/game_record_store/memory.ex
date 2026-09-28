defmodule Analysis.GameRecordStore.Memory do
  @moduledoc """
  In-memory reference implementation of GameRecordStore.
  """

  use GenServer

  @behaviour Analysis.GameRecordStore

  alias Analysis.GameRecord

  @type store :: GenServer.server()

  @spec start_link(keyword()) ::
          GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(
      __MODULE__,
      %{},
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

  @impl true
  def init(records) do
    {:ok, records}
  end

  @impl true
  def handle_call(
        :ping,
        _from,
        records
      ) do
    {
      :reply,
      :ok,
      records
    }
  end

  @impl true
  def handle_call(
        {:insert, %GameRecord{id: id} = record},
        _from,
        records
      ) do
    if Map.has_key?(
         records,
         id
       ) do
      {
        :reply,
        {:error, :already_exists},
        records
      }
    else
      {
        :reply,
        :ok,
        Map.put(
          records,
          id,
          record
        )
      }
    end
  end

  def handle_call(
        {:get, record_id},
        _from,
        records
      ) do
    reply =
      case Map.fetch(
             records,
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
      records
    }
  end

  def handle_call(
        :list,
        _from,
        records
      ) do
    {
      :reply,
      Map.values(records),
      records
    }
  end
end
