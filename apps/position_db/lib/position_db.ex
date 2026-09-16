defmodule PositionDB do
  alias PositionDB.EquivalenceContext
  alias PositionDB.PositionIndexer
  alias PositionDB.PositionStore
  alias PositionDB.QueryEngine

  @type position_id :: non_neg_integer()

  @type matcher :: (term(), term() -> boolean())

  @type t :: %__MODULE__{
          store: PositionStore.t(),
          indexer: PositionIndexer.t(),
          equivalence: EquivalenceContext.t()
        }

  defstruct [
    :store,
    :indexer,
    :equivalence
  ]

  def new(options) do
    key_function = Keyword.fetch!(options, :key_function)
    properties = Keyword.fetch!(options, :properties)

    equivalence_function =
      Keyword.get(options, :equivalence_function, key_function)

    matcher =
      Keyword.get(options, :matcher, &(&1 == &2))

    %__MODULE__{
      store: PositionStore.new(key_function),
      indexer: PositionIndexer.new(properties),
      equivalence:
        EquivalenceContext.new(
          equivalence_function,
          matcher
        )
    }
  end

  def put(db, position) do
    {store, position_id} =
      PositionStore.put(db.store, position)

    indexer =
      PositionIndexer.index(
        db.indexer,
        position_id,
        position
      )

    equivalence =
      EquivalenceContext.add(
        db.equivalence,
        position,
        position_id
      )

    {
      %{
        db
        | store: store,
          indexer: indexer,
          equivalence: equivalence
      },
      position_id
    }
  end

  @spec delete(t(), position_id()) :: t()
  def delete(%__MODULE__{} = db, position_id) do
    case PositionStore.get(db.store, position_id) do
      :not_found ->
        db

      {:ok, position} ->
        %{
          db
          | store: PositionStore.delete(db.store, position_id),
            indexer: PositionIndexer.delete(db.indexer, position_id, position),
            equivalence:
              EquivalenceContext.delete(
                db.equivalence,
                position,
                position_id
              )
        }
    end
  end

  def get(db, position_id) do
    PositionStore.get(db.store, position_id)
  end

  def find(db, position) do
    PositionStore.find(db.store, position)
  end

  def query(db, query) do
    QueryEngine.execute(
      db.indexer.index,
      db.store,
      query,
      db.equivalence
    )
  end
end
