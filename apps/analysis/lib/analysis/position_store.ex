defmodule Analysis.PositionStore do
  @moduledoc false

  use GenServer

  alias Analysis.PositionDatabase

  alias Chess.PositionKey
  alias Chess.PositionProperties

  @name __MODULE__

  @registry Analysis.PositionStoreRegistry
  @registry_key :position_store

  @spec clustered_server() :: GenServer.server()
  def clustered_server do
    {:via, Horde.Registry, {@registry, @registry_key}}
  end

  @spec start_link(keyword()) :: GenServer.on_start()
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

  @spec server() :: GenServer.server()
  def server do
    Application.get_env(
      :analysis,
      __MODULE__,
      []
    )
    |> Keyword.get(
      :server,
      clustered_server()
    )
  end

  @spec ready?() :: boolean()
  def ready? do
    try do
      GenServer.call(
        server(),
        :ping,
        1_000
      ) == :ok
    catch
      :exit, _reason ->
        false
    end
  end

  @spec get(PositionDB.position_id()) ::
          {:ok, Chess.Position.t()}
          | :not_found
          | {:error, term()}
  def get(position_id) do
    GenServer.call(
      server(),
      {:get, position_id}
    )
  end

  @spec append(Chess.Position.t()) ::
          PositionDB.position_id()
          | {:error, term()}
  def append(position) do
    GenServer.call(
      server(),
      {:append, position}
    )
  end

  @impl true
  def init(opts) do
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

  @impl true
  def handle_call(
        :ping,
        _from,
        db
      ) do
    {:reply, :ok, db}
  end

  @impl true
  def handle_call(
        {:get, position_id},
        _from,
        db
      ) do
    {:reply,
     PositionDB.get(
       db,
       position_id
     ), db}
  end

  def handle_call(
        {:append, position},
        _from,
        db
      ) do
    case PositionDB.append(
           db,
           position
         ) do
      {%PositionDB{} = db, position_id} ->
        {:reply, position_id, db}

      {:error, reason} ->
        {:stop, {:position_database_write_failed, reason}, {:error, reason}, db}
    end
  end

  defp init_persistent(
         directory,
         opts
       ) do
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
end
