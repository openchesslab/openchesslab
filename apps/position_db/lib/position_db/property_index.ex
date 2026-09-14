defmodule PositionDB.PropertyIndex do
  @moduledoc """
  In-memory index from property values to position identifiers.
  """

  @type property :: {atom(), term()}
  @type position_id :: term()
  @type t :: %{property() => MapSet.t(position_id())}

  @spec new() :: t()
  def new, do: %{}

  @spec add(t(), property(), position_id()) :: t()
  def add(index, property, position_id) do
    Map.update(
      index,
      property,
      MapSet.new([position_id]),
      &MapSet.put(&1, position_id)
    )
  end

  @spec lookup(t(), property()) :: MapSet.t(position_id())
  def lookup(index, property) do
    Map.get(index, property, MapSet.new())
  end
end
