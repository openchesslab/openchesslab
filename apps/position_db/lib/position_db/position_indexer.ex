defmodule PositionDB.PositionIndexer do
  @moduledoc """
  Indexes configured position properties.
  """

  alias PositionDB.PropertyIndex

  @type position_id :: pos_integer()
  @type property ::
          {atom(), (term() -> term())}

  @type indexed_property ::
          {atom(), term()}

  @type t :: %__MODULE__{
          properties: [property()],
          index: PropertyIndex.t()
        }

  defstruct [
    :properties,
    :index
  ]

  @spec new([property()]) :: t()
  def new(properties) do
    new(
      properties,
      PropertyIndex.new()
    )
  end

  @spec new(
          [property()],
          PropertyIndex.t()
        ) :: t()
  def new(
        properties,
        %PropertyIndex{} = index
      ) do
    %__MODULE__{
      properties: properties,
      index: index
    }
  end

  @spec properties_for(
          t(),
          term()
        ) ::
          [indexed_property()]
  def properties_for(
        %__MODULE__{} = indexer,
        position
      ) do
    Enum.flat_map(
      indexer.properties,
      fn {name, property} ->
        case property.(position) do
          values
          when is_list(values) ->
            Enum.map(
              values,
              &{name, &1}
            )

          value ->
            [
              {
                name,
                value
              }
            ]
        end
      end
    )
  end

  @spec index(
          t(),
          position_id(),
          term()
        ) ::
          t()
          | {:error, term()}
  def index(
        %__MODULE__{} = indexer,
        position_id,
        position
      ) do
    case index_properties(
           properties_for(
             indexer,
             position
           ),
           indexer.index,
           position_id
         ) do
      {:ok, index} ->
        %{
          indexer
          | index: index
        }

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp index_properties(
         properties,
         index,
         position_id
       ) do
    Enum.reduce_while(
      properties,
      {:ok, index},
      fn {name, value}, {:ok, index} ->
        case PropertyIndex.add_result(
               index,
               {name, value},
               position_id
             ) do
          {:ok, next_index} ->
            {:cont, {:ok, next_index}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end
    )
  end
end
