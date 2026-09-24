defmodule PositionDB.PropertyIndexScan do
  @moduledoc """
  Executes a lazy scan over position IDs matching a property.
  """

  alias PositionDB.PropertyIndex
  alias PositionDB.QueryExecutor

  @type property ::
          {atom(), term()}

  @type t :: %__MODULE__{
          index: PropertyIndex.t(),
          property: property(),
          ids:
            [pos_integer()]
            | nil
        }

  defstruct [
    :index,
    :property,
    ids: nil
  ]

  @spec new(
          PropertyIndex.t(),
          property()
        ) ::
          QueryExecutor.t()
  def new(
        %PropertyIndex{} = index,
        property
      ) do
    QueryExecutor.new(
      __MODULE__,
      %__MODULE__{
        index: index,
        property: property
      }
    )
  end

  @spec next(t()) ::
          {:ok, pos_integer(), t()}
          | :done
          | {:error, term()}
  def next(
        %__MODULE__{
          ids: nil
        } = state
      ) do
    case PropertyIndex.lookup_ids(
           state.index,
           state.property
         ) do
      {:ok, ids} ->
        next(%{
          state
          | ids: ids
        })

      {:error, reason} ->
        {:error, reason}
    end
  end

  def next(
        %__MODULE__{
          ids: [position_id | rest]
        } = state
      ) do
    {:ok, position_id,
     %{
       state
       | ids: rest
     }}
  end

  def next(%__MODULE__{
        ids: []
      }) do
    :done
  end
end
