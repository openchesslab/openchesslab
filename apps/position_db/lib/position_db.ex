defmodule PositionDB do
  @moduledoc """
  Database for chess positions.
  """

  alias PositionDB.QueryEngine
  alias PositionDB.PropertyIndex
  alias PositionDB.PositionIndexer
  alias PositionDB.PositionStore

  @type position_id :: non_neg_integer()

  @type t :: %__MODULE__{
          store: PositionStore.t(),
          indexer: PositionIndexer.t()
        }

  defstruct [:store, :indexer]

  @spec new(
          key_function: (term() -> term()),
          properties: [{atom(), (term() -> [term()])}]
        ) :: t()
  def new(key_function: key_function, properties: properties) do
    %__MODULE__{
      store: PositionStore.new(key_function),
      indexer: PositionIndexer.new(properties)
    }
  end

  @spec put(t(), term()) :: {t(), position_id()}
  def put(%__MODULE__{} = db, position) do
    {store, position_id} = PositionStore.put(db.store, position)

    indexer =
      PositionIndexer.index(
        db.indexer,
        position_id,
        position
      )

    {%{db | store: store, indexer: indexer}, position_id}
  end

  @spec get(t(), position_id()) :: {:ok, term()} | :not_found
  def get(%__MODULE__{} = db, position_id) do
    PositionStore.get(db.store, position_id)
  end

  @spec find(t(), term()) :: {:ok, position_id()} | :not_found
  def find(%__MODULE__{} = db, position) do
    PositionStore.find(db.store, position)
  end

  @spec find_by_property(t(), atom(), term()) :: MapSet.t(position_id())
  def find_by_property(%__MODULE__{} = db, property, value) do
    PropertyIndex.lookup(
      db.indexer.index,
      {property, value}
    )
  end

  @spec query(t(), PositionDB.Query.t()) :: MapSet.t(position_id())
  def query(%__MODULE__{} = db, query) do
    QueryEngine.execute(
      db.indexer.index,
      db.store,
      query
    )
  end
end
