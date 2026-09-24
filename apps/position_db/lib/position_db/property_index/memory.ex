defmodule PositionDB.PropertyIndex.Memory do
  @moduledoc """
  In-memory property-index backend.
  """

  @behaviour PositionDB.PropertyIndex.Backend

  @type property :: {atom(), term()}
  @type position_id :: pos_integer()

  @type t :: %__MODULE__{
          entries: %{
            property() => MapSet.t(position_id())
          }
        }

  defstruct entries: %{}

  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @impl PositionDB.PropertyIndex.Backend
  def add(
        %__MODULE__{} = index,
        property,
        position_id
      )
      when is_integer(position_id) and
             position_id > 0 do
    entries =
      Map.update(
        index.entries,
        property,
        MapSet.new([position_id]),
        &MapSet.put(
          &1,
          position_id
        )
      )

    {:ok,
     %{
       index
       | entries: entries
     }}
  end

  @impl PositionDB.PropertyIndex.Backend
  def lookup(
        %__MODULE__{} = index,
        property
      ) do
    position_ids =
      index.entries
      |> Map.get(
        property,
        MapSet.new()
      )
      |> MapSet.to_list()
      |> Enum.sort()

    {:ok, position_ids}
  end

  @impl PositionDB.PropertyIndex.Backend
  def cardinality(
        %__MODULE__{} = index,
        property
      ) do
    count =
      index.entries
      |> Map.get(
        property,
        MapSet.new()
      )
      |> MapSet.size()

    {:ok, count}
  end
end
