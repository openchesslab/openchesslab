defmodule Analysis.GameRecordStore.Memory do
  @moduledoc """
  In-memory reference implementation of GameRecordStore.
  """

  @behaviour Analysis.GameRecordStore

  use GenServer

  alias Analysis.GameRecord
  alias Analysis.GameRecordStore
  alias Analysis.GameRepository

  @type store :: GenServer.server()

  @opaque record_cursor :: reference()

  defmodule CursorState do
    @moduledoc false

    @enforce_keys [:record_ids]

    @type t :: %__MODULE__{
            record_ids: [GameRecord.id()]
          }

    defstruct record_ids: []
  end

  @type t :: %__MODULE__{
          records: %{
            GameRecord.id() => GameRecord.t()
          },
          record_ids_by_game: %{
            GameRepository.game_id() => [GameRecord.id()]
          },
          cursors: %{
            record_cursor() => CursorState.t()
          }
        }

  defstruct records: %{},
            record_ids_by_game: %{},
            cursors: %{}

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

  @impl GameRecordStore
  @spec insert(
          store(),
          GameRecord.t()
        ) ::
          :ok
          | {:error, :already_exists}
  def insert(store, %GameRecord{} = record) do
    GenServer.call(
      store,
      {:insert, record}
    )
  end

  @impl GameRecordStore
  @spec get(
          store(),
          GameRecord.id()
        ) ::
          {:ok, GameRecord.t()}
          | :not_found
  def get(store, record_id) do
    GenServer.call(
      store,
      {:get, record_id}
    )
  end

  @impl GameRecordStore
  @spec list(store()) ::
          [GameRecord.t()]
  def list(store) do
    GenServer.call(
      store,
      :list
    )
  end

  @impl GameRecordStore
  @spec list_by_game_id(
          store(),
          GameRepository.game_id()
        ) ::
          [GameRecord.t()]
  def list_by_game_id(store, game_id) do
    GenServer.call(
      store,
      {:list_by_game_id, game_id}
    )
  end

  @impl GameRecordStore
  @spec records_page_by_game_id(
          store(),
          GameRepository.game_id(),
          pos_integer()
        ) ::
          GameRecordStore.record_page()
  def records_page_by_game_id(store, game_id, page_size)
      when is_integer(page_size) and page_size > 0 do
    GenServer.call(
      store,
      {
        :records_page_by_game_id,
        game_id,
        page_size
      }
    )
  end

  @impl GameRecordStore
  @spec next_records_page(
          store(),
          GameRecordStore.record_cursor(),
          pos_integer()
        ) ::
          GameRecordStore.record_page()
  def next_records_page(store, cursor, page_size)
      when is_reference(cursor) and is_integer(page_size) and page_size > 0 do
    GenServer.call(
      store,
      {
        :next_records_page,
        cursor,
        page_size
      }
    )
  end

  @impl GameRecordStore
  @spec close_record_scan(
          store(),
          GameRecordStore.record_cursor()
        ) ::
          :ok
  def close_record_scan(store, cursor) when is_reference(cursor) do
    GenServer.call(
      store,
      {
        :close_record_scan,
        cursor
      }
    )
  end

  @impl true
  def init(%__MODULE__{} = state) do
    {:ok, state}
  end

  @impl true
  def handle_call(:ping, _from, state) do
    {
      :reply,
      :ok,
      state
    }
  end

  def handle_call({:insert, %GameRecord{id: id} = record}, _from, state) do
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
              [id],
              &[id | &1]
            )
      }

      {
        :reply,
        :ok,
        updated_state
      }
    end
  end

  def handle_call({:get, record_id}, _from, state) do
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

  def handle_call(:list, _from, state) do
    {
      :reply,
      Map.values(state.records),
      state
    }
  end

  def handle_call({:list_by_game_id, game_id}, _from, state) do
    records =
      state.record_ids_by_game
      |> Map.get(
        game_id,
        []
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

  def handle_call({:records_page_by_game_id, game_id, page_size}, _from, state) do
    cursor_state =
      %CursorState{
        record_ids:
          Map.get(
            state.record_ids_by_game,
            game_id,
            []
          )
      }

    case take_records_page(
           state.records,
           cursor_state,
           page_size
         ) do
      {:ok, records, :done} ->
        {
          :reply,
          {
            :ok,
            records,
            :done
          },
          state
        }

      {
        :ok,
        records,
        %CursorState{} = cursor_state
      } ->
        cursor =
          make_ref()

        {
          :reply,
          {
            :ok,
            records,
            cursor
          },
          put_cursor(
            state,
            cursor,
            cursor_state
          )
        }

      {:error, reason} ->
        {
          :reply,
          {:error, reason},
          state
        }
    end
  end

  def handle_call({:next_records_page, cursor, page_size}, _from, state) do
    case Map.fetch(
           state.cursors,
           cursor
         ) do
      {:ok, cursor_state} ->
        continue_records_page(
          state,
          cursor,
          cursor_state,
          page_size
        )

      :error ->
        {
          :reply,
          {:error, :cursor_not_found},
          state
        }
    end
  end

  def handle_call({:close_record_scan, cursor}, _from, state) do
    {
      :reply,
      :ok,
      delete_cursor(
        state,
        cursor
      )
    }
  end

  defp continue_records_page(state, cursor, cursor_state, page_size) do
    case take_records_page(
           state.records,
           cursor_state,
           page_size
         ) do
      {:ok, records, :done} ->
        {
          :reply,
          {
            :ok,
            records,
            :done
          },
          delete_cursor(
            state,
            cursor
          )
        }

      {
        :ok,
        records,
        %CursorState{} = cursor_state
      } ->
        {
          :reply,
          {
            :ok,
            records,
            cursor
          },
          put_cursor(
            state,
            cursor,
            cursor_state
          )
        }

      {:error, reason} ->
        {
          :reply,
          {:error, reason},
          delete_cursor(
            state,
            cursor
          )
        }
    end
  end

  defp take_records_page(records, cursor_state, page_size) do
    take_records_page(
      records,
      cursor_state,
      page_size,
      []
    )
  end

  defp take_records_page(_records, %CursorState{record_ids: []}, _remaining, reversed_records) do
    {
      :ok,
      Enum.reverse(reversed_records),
      :done
    }
  end

  defp take_records_page(_records, %CursorState{} = cursor_state, 0, reversed_records) do
    {
      :ok,
      Enum.reverse(reversed_records),
      cursor_state
    }
  end

  defp take_records_page(
         records,
         %CursorState{record_ids: [record_id | remaining_record_ids]} = cursor_state,
         remaining,
         reversed_records
       ) do
    case Map.fetch(
           records,
           record_id
         ) do
      {:ok, record} ->
        take_records_page(
          records,
          %{
            cursor_state
            | record_ids: remaining_record_ids
          },
          remaining - 1,
          [
            record
            | reversed_records
          ]
        )

      :error ->
        {:error, :record_not_found}
    end
  end

  defp put_cursor(state, cursor, cursor_state) do
    %{
      state
      | cursors:
          Map.put(
            state.cursors,
            cursor,
            cursor_state
          )
    }
  end

  defp delete_cursor(state, cursor) do
    %{
      state
      | cursors:
          Map.delete(
            state.cursors,
            cursor
          )
    }
  end
end
