defmodule PositionDB.Storage.ExactIndex.Memory do
  @moduledoc """
  In-memory reference implementation of the exact position index.
  """

  @behaviour PositionDB.Storage.ExactIndex

  @type t :: %__MODULE__{
          entries: %{binary() => MapSet.t(pos_integer())}
        }

  defstruct entries: %{}

  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @impl PositionDB.Storage.ExactIndex
  def add(
        %__MODULE__{} = index,
        key,
        position_id
      )
      when is_binary(key) and
             is_integer(position_id) and
             position_id > 0 do
    entries =
      Map.update(
        index.entries,
        key,
        MapSet.new([position_id]),
        &MapSet.put(&1, position_id)
      )

    {:ok, %{index | entries: entries}}
  end

  @impl PositionDB.Storage.ExactIndex
  def lookup(
        %__MODULE__{} = index,
        key
      )
      when is_binary(key) do
    position_ids =
      index.entries
      |> Map.get(key, MapSet.new())
      |> MapSet.to_list()

    {:ok, position_ids}
  end
end
