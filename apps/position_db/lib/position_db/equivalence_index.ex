defmodule PositionDB.EquivalenceIndex do
  @moduledoc """
  Indexes position IDs by an equivalence key.
  """

  @type position_id :: non_neg_integer()
  @type equivalence_key :: term()
  @type t :: %{equivalence_key() => MapSet.t(position_id())}

  @spec new() :: t()
  def new, do: %{}

  @spec add(t(), equivalence_key(), position_id()) :: t()
  def add(index, key, position_id) do
    Map.update(
      index,
      key,
      MapSet.new([position_id]),
      &MapSet.put(&1, position_id)
    )
  end

  @spec delete(t(), equivalence_key(), position_id()) :: t()
  def delete(index, key, position_id) do
    case Map.get(index, key) do
      nil ->
        index

      positions ->
        positions = MapSet.delete(positions, position_id)

        if MapSet.size(positions) == 0 do
          Map.delete(index, key)
        else
          Map.put(index, key, positions)
        end
    end
  end

  @spec lookup(t(), equivalence_key()) :: MapSet.t(position_id())
  def lookup(index, key) do
    Map.get(index, key, MapSet.new())
  end
end
