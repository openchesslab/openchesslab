defmodule Analysis.PositionStore do
  @moduledoc false

  use GenServer

  alias Chess.PositionKey
  alias Chess.PositionProperties

  @name __MODULE__

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  @spec get(PositionDB.position_id()) ::
          {:ok, Chess.Position.t()} | :not_found
  def get(position_id) do
    GenServer.call(@name, {:get, position_id})
  end

  @spec append(Chess.Position.t()) :: PositionDB.position_id()
  def append(position) do
    GenServer.call(@name, {:append, position})
  end

  @impl true
  def init(_opts) do
    {:ok, new_db()}
  end

  @impl true
  def handle_call({:get, position_id}, _from, db) do
    {:reply, PositionDB.get(db, position_id), db}
  end

  @impl true
  def handle_call({:append, position}, _from, db) do
    {db, position_id} = PositionDB.append(db, position)

    {:reply, position_id, db}
  end

  defp new_db do
    PositionDB.new(
      key_function: &PositionKey.exact/1,
      properties: [
        {:open_files, &PositionProperties.open_files/1},
        {:material, &PositionProperties.material/1}
      ]
    )
  end
end
