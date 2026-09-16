defmodule PositionDB.PositionIndexer do
  @moduledoc """
  Indexes configured position properties.
  """

  alias PositionDB.PropertyIndex

  @type position_id :: term()
  @type property :: {atom(), (term() -> term())}

  @type t :: %__MODULE__{
          properties: [property()],
          index: PropertyIndex.t()
        }

  defstruct [:properties, :index]

  @spec new([property()]) :: t()
  def new(properties) do
    %__MODULE__{
      properties: properties,
      index: PropertyIndex.new()
    }
  end

  @spec index(t(), position_id(), term()) :: t()
  def index(%__MODULE__{} = indexer, position_id, position) do
    index =
      Enum.reduce(indexer.properties, indexer.index, fn {name, property}, index ->
        values =
          case property.(position) do
            values when is_list(values) -> values
            value -> [value]
          end

        Enum.reduce(values, index, fn value, index ->
          PropertyIndex.add(index, {name, value}, position_id)
        end)
      end)

    %{indexer | index: index}
  end
end
