defmodule Analysis.PositionStore do
  @moduledoc """
  Application-facing access to canonical chess positions.

  PostgreSQL repositories are stateless and are called directly from
  every application node.

  The legacy PositionDB-backed GenServer remains temporarily available
  as the reference implementation while the PostgreSQL migration is
  completed.
  """

  use GenServer

  alias Analysis.PositionDatabase
  alias Chess.PositionKey
  alias Chess.PositionProperties
  alias PositionDB.QueryResult

  @name __MODULE__

  @registry Analysis.PositionStoreRegistry
  @registry_key :position_store

  @opaque query_cursor :: term()

  @type query_page ::
          {:ok, [PositionDB.position_id()], :done | query_cursor()}
          | {:error, term()}

  defmodule State do
    @moduledoc false

    @enforce_keys [:db]

    defstruct db: nil,
              cursors: %{}
  end

  defmodule CursorState do
    @moduledoc false

    @enforce_keys [:result]

    defstruct result: nil,
              pending_position_id: nil
  end

  @spec clustered_server() :: GenServer.server()
  def clustered_server do
    {
      :via,
      Horde.Registry,
      {
        @registry,
        @registry_key
      }
    }
  end

  @spec start_link(keyword()) ::
          GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(
      __MODULE__,
      opts,
      name:
        Keyword.get(
          opts,
          :server,
          @name
        )
    )
  end

  @spec server() ::
          GenServer.server()
  def server do
    :analysis
    |> Application.get_env(
      __MODULE__,
      []
    )
    |> Keyword.get(
      :server,
      clustered_server()
    )
  end

  @spec repository() ::
          module()
          | nil
  def repository do
    :analysis
    |> Application.get_env(
      __MODULE__,
      []
    )
    |> Keyword.get(:repository)
  end

  @spec repository_configured?() :: boolean()
  def repository_configured? do
    not is_nil(repository())
  end

  @spec ready?() :: boolean()
  def ready? do
    case repository() do
      nil ->
        legacy_ready?()

      repository ->
        repository.ready?()
    end
  end

  @spec get(PositionDB.position_id()) ::
          {:ok, Chess.Position.t()}
          | :not_found
          | {:error, term()}
  def get(position_id) do
    case repository() do
      nil ->
        GenServer.call(
          server(),
          {:get, position_id}
        )

      repository ->
        repository.get(position_id)
    end
  end

  @spec find(Chess.Position.t()) ::
          {:ok, PositionDB.position_id()}
          | :not_found
          | {:error, term()}
  def find(position) do
    case repository() do
      nil ->
        GenServer.call(
          server(),
          {:find, position}
        )

      repository ->
        repository.find(position)
    end
  end

  @spec query_page(
          PositionDB.Query.t(),
          pos_integer()
        ) ::
          query_page()
  def query_page(query, page_size) when is_integer(page_size) and page_size > 0 do
    case repository() do
      nil ->
        GenServer.call(
          server(),
          {
            :query_page,
            query,
            page_size
          }
        )

      repository ->
        repository.query_page(
          query,
          page_size
        )
    end
  end

  @spec next_query_page(
          query_cursor(),
          pos_integer()
        ) ::
          query_page()
  def next_query_page(cursor, page_size) when is_integer(page_size) and page_size > 0 do
    case repository() do
      nil ->
        GenServer.call(
          server(),
          {
            :next_query_page,
            cursor,
            page_size
          }
        )

      repository ->
        repository.next_query_page(
          cursor,
          page_size
        )
    end
  end

  @spec close_query(query_cursor()) :: :ok
  def close_query(cursor) do
    case repository() do
      nil ->
        GenServer.call(
          server(),
          {
            :close_query,
            cursor
          }
        )

      repository ->
        repository.close_query(cursor)
    end
  end

  @spec append(Chess.Position.t()) ::
          PositionDB.position_id()
          | {:error, term()}
  def append(position) do
    case repository() do
      nil ->
        GenServer.call(
          server(),
          {:append, position}
        )

      repository ->
        case repository.put(position) do
          {:ok, position_id} ->
            position_id

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @impl true
  def init(opts) do
    case init_db(opts) do
      {:ok, db} ->
        {:ok,
         %State{
           db: db
         }}

      {:stop, _reason} = error ->
        error
    end
  end

  @impl true
  def handle_call(:ping, _from, %State{} = state) do
    {
      :reply,
      :ok,
      state
    }
  end

  def handle_call({:get, position_id}, _from, %State{db: db} = state) do
    {
      :reply,
      PositionDB.get(
        db,
        position_id
      ),
      state
    }
  end

  def handle_call({:find, position}, _from, %State{db: db} = state) do
    {
      :reply,
      PositionDB.find(
        db,
        position
      ),
      state
    }
  end

  def handle_call({:append, position}, _from, %State{db: db} = state) do
    case PositionDB.append(
           db,
           position
         ) do
      {%PositionDB{} = db, position_id} ->
        {
          :reply,
          position_id,
          %{
            state
            | db: db
          }
        }

      {:error, reason} ->
        {
          :stop,
          {
            :position_database_write_failed,
            reason
          },
          {:error, reason},
          state
        }
    end
  end

  def handle_call({:query_page, query, page_size}, _from, %State{db: db} = state) do
    cursor_state =
      %CursorState{
        result:
          PositionDB.query(
            db,
            query
          )
      }

    case take_page(
           cursor_state,
           page_size
         ) do
      {:ok, position_ids, :done} ->
        {
          :reply,
          {
            :ok,
            position_ids,
            :done
          },
          state
        }

      {
        :ok,
        position_ids,
        %CursorState{} = cursor_state
      } ->
        cursor =
          make_ref()

        {
          :reply,
          {
            :ok,
            position_ids,
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

  def handle_call({:next_query_page, cursor, page_size}, _from, %State{} = state) do
    case Map.fetch(
           state.cursors,
           cursor
         ) do
      {:ok, cursor_state} ->
        continue_query(
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

  def handle_call({:close_query, cursor}, _from, %State{} = state) do
    {
      :reply,
      :ok,
      delete_cursor(
        state,
        cursor
      )
    }
  end

  defp legacy_ready? do
    GenServer.call(
      server(),
      :ping,
      1_000
    ) == :ok
  rescue
    ArgumentError ->
      false
  catch
    :exit, _reason ->
      false
  end

  defp init_db(opts) do
    case Keyword.fetch(
           opts,
           :directory
         ) do
      {:ok, directory} ->
        init_persistent(
          directory,
          opts
        )

      :error ->
        {:ok, new_memory_db()}
    end
  end

  defp init_persistent(directory, opts) do
    case PositionDatabase.open_or_create(
           directory,
           opts
         ) do
      {:ok, db} ->
        {:ok, db}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  defp new_memory_db do
    PositionDB.new(
      key_function: &PositionKey.exact/1,
      properties: [
        {
          :open_files,
          &PositionProperties.open_files/1
        },
        {
          :material,
          &PositionProperties.material/1
        }
      ]
    )
  end

  defp continue_query(state, cursor, cursor_state, page_size) do
    case take_page(
           cursor_state,
           page_size
         ) do
      {:ok, position_ids, :done} ->
        {
          :reply,
          {
            :ok,
            position_ids,
            :done
          },
          delete_cursor(
            state,
            cursor
          )
        }

      {
        :ok,
        position_ids,
        %CursorState{} = cursor_state
      } ->
        {
          :reply,
          {
            :ok,
            position_ids,
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

  defp take_page(cursor_state, page_size) do
    take_page(
      cursor_state,
      page_size,
      []
    )
  end

  defp take_page(cursor_state, 0, reversed_position_ids) do
    finish_page(
      cursor_state,
      reversed_position_ids
    )
  end

  defp take_page(cursor_state, remaining, reversed_position_ids) do
    case next_position(cursor_state) do
      {
        :ok,
        position_id,
        cursor_state
      } ->
        take_page(
          cursor_state,
          remaining - 1,
          [
            position_id
            | reversed_position_ids
          ]
        )

      :done ->
        {
          :ok,
          Enum.reverse(reversed_position_ids),
          :done
        }

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp finish_page(cursor_state, reversed_position_ids) do
    case next_position(cursor_state) do
      {
        :ok,
        position_id,
        cursor_state
      } ->
        {
          :ok,
          Enum.reverse(reversed_position_ids),
          %{
            cursor_state
            | pending_position_id: position_id
          }
        }

      :done ->
        {
          :ok,
          Enum.reverse(reversed_position_ids),
          :done
        }

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp next_position(%CursorState{pending_position_id: position_id} = cursor_state)
       when not is_nil(position_id) do
    {
      :ok,
      position_id,
      %{
        cursor_state
        | pending_position_id: nil
      }
    }
  end

  defp next_position(%CursorState{result: result} = cursor_state) do
    case QueryResult.next(result) do
      {
        :ok,
        position_id,
        result
      } ->
        {
          :ok,
          position_id,
          %{
            cursor_state
            | result: result
          }
        }

      :done ->
        :done

      {:error, reason} ->
        {:error, reason}
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
