defmodule PositionDB.Storage.PostingIndex.Memory do
  @moduledoc """
  In-memory reference implementation of the posting index.
  """

  @behaviour PositionDB.Storage.PostingIndex

  @type t :: %__MODULE__{
          entries: %{
            binary() => MapSet.t(pos_integer())
          }
        }

  defstruct entries: %{}

  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @impl PositionDB.Storage.PostingIndex
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

  @impl PositionDB.Storage.PostingIndex
  def lookup(
        %__MODULE__{} = index,
        key
      )
      when is_binary(key) do
    position_ids =
      index.entries
      |> Map.get(
        key,
        MapSet.new()
      )
      |> MapSet.to_list()
      |> Enum.sort()

    {:ok, position_ids}
  end

  @impl PositionDB.Storage.PostingIndex
  def cardinality(
        %__MODULE__{} = index,
        key
      )
      when is_binary(key) do
    count =
      index.entries
      |> Map.get(
        key,
        MapSet.new()
      )
      |> MapSet.size()

    {:ok, count}
  end
end
