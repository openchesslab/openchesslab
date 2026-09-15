defmodule PositionDB do
  alias PositionDB.EquivalenceIndex
  alias PositionDB.PositionIndexer
  alias PositionDB.PositionStore
  alias PositionDB.PropertyIndex
  alias PositionDB.QueryEngine

  @type position_id :: non_neg_integer()

  @type matcher :: (term(), term() -> boolean())

  @type t :: %__MODULE__{
          store: PositionStore.t(),
          indexer: PositionIndexer.t(),
          equivalence_index: EquivalenceIndex.t(),
          equivalence_function: (term() -> term()),
          matcher: matcher()
        }

  defstruct [
    :store,
    :indexer,
    :equivalence_index,
    :equivalence_function,
    :matcher
  ]

  def new(options) do
    key_function = Keyword.fetch!(options, :key_function)
    properties = Keyword.fetch!(options, :properties)
    equivalence_function = Keyword.get(options, :equivalence_function, key_function)
    matcher = Keyword.get(options, :matcher, &(&1 == &2))

    %__MODULE__{
      store: PositionStore.new(key_function),
      indexer: PositionIndexer.new(properties),
      equivalence_index: EquivalenceIndex.new(),
      equivalence_function: equivalence_function,
      matcher: matcher
    }
  end

  def put(db, position) do
    {store, position_id} = PositionStore.put(db.store, position)

    indexer =
      PositionIndexer.index(
        db.indexer,
        position_id,
        position
      )

    equivalence_key = db.equivalence_function.(position)

    equivalence_index =
      EquivalenceIndex.add(
        db.equivalence_index,
        equivalence_key,
        position_id
      )

    {
      %{
        db
        | store: store,
          indexer: indexer,
          equivalence_index: equivalence_index
      },
      position_id
    }
  end

  def get(db, position_id), do: PositionStore.get(db.store, position_id)

  def find(db, position), do: PositionStore.find(db.store, position)

  def find_by_property(db, property, value) do
    PropertyIndex.lookup(db.indexer.index, {property, value})
  end

  def find_equivalent_candidates(db, position) do
    position
    |> db.equivalence_function.()
    |> then(&EquivalenceIndex.lookup(db.equivalence_index, &1))
  end

  @spec find_equivalent(t(), term()) :: MapSet.t(position_id())
  def find_equivalent(db, position) do
    candidate_ids = find_equivalent_candidates(db, position)

    candidate_ids
    |> Enum.filter(fn position_id ->
      case PositionStore.get(db.store, position_id) do
        {:ok, candidate} ->
          db.matcher.(position, candidate)

        :not_found ->
          false
      end
    end)
    |> MapSet.new()
  end

  def query(db, query) do
    QueryEngine.execute(db.indexer.index, db.store, query)
  end
end
