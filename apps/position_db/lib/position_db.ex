defmodule PositionDB do
  alias PositionDB.EquivalenceIndex
  alias PositionDB.PositionIndexer
  alias PositionDB.PositionStore
  alias PositionDB.QueryEngine
  alias PositionDB.QueryResult
  alias PositionDB.PropertyIndex

  @type position_id :: non_neg_integer()
  @type matcher :: (term(), term() -> boolean())
  @type equivalence_function :: (term() -> term())

  @type t :: %__MODULE__{
          store: PositionStore.t(),
          indexer: PositionIndexer.t(),
          equivalence_index: EquivalenceIndex.t(),
          equivalence_function: equivalence_function(),
          matcher: matcher()
        }

  defstruct [
    :store,
    :indexer,
    :equivalence_index,
    :equivalence_function,
    :matcher
  ]

  @spec new(keyword()) :: t()
  def new(options) do
    key_function = Keyword.fetch!(options, :key_function)
    properties = Keyword.fetch!(options, :properties)

    equivalence_function =
      Keyword.get(
        options,
        :equivalence_function,
        key_function
      )

    matcher =
      Keyword.get(
        options,
        :matcher,
        &(&1 == &2)
      )

    %__MODULE__{
      store: PositionStore.new(key_function),
      indexer: PositionIndexer.new(properties),
      equivalence_index: EquivalenceIndex.new(),
      equivalence_function: equivalence_function,
      matcher: matcher
    }
  end

  @spec put(t(), term()) :: {t(), position_id()}
  def put(db, position) do
    {store, position_id} =
      PositionStore.put(
        db.store,
        position
      )

    indexer =
      PositionIndexer.index(
        db.indexer,
        position_id,
        position
      )

    equivalence_key =
      db.equivalence_function.(position)

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

  @spec get(t(), position_id()) ::
          {:ok, term()}
          | :not_found
  def get(db, position_id) do
    PositionStore.get(
      db.store,
      position_id
    )
  end

  @spec find(t(), term()) ::
          {:ok, position_id()}
          | :not_found
  def find(db, position) do
    PositionStore.find(
      db.store,
      position
    )
  end

  @spec query(t(), PositionDB.Query.t()) :: QueryResult.t()
  def query(db, query) do
    QueryEngine.execute(
      db.indexer.index,
      db.store,
      query,
      %{
        equivalence_index: db.equivalence_index,
        equivalence_function: db.equivalence_function,
        matcher: db.matcher
      }
    )
  end

  @spec find_by_property(t(), atom(), term()) ::
          MapSet.t(position_id())
  def find_by_property(db, property, value) do
    PropertyIndex.lookup(
      db.indexer.index,
      {property, value}
    )
  end

  @spec find_equivalent_candidates(t(), term()) ::
          MapSet.t(position_id())
  def find_equivalent_candidates(db, position) do
    position
    |> db.equivalence_function.()
    |> then(&EquivalenceIndex.lookup(db.equivalence_index, &1))
  end

  @spec find_equivalent(t(), term()) ::
          MapSet.t(position_id())
  def find_equivalent(db, position) do
    candidate_ids =
      find_equivalent_candidates(
        db,
        position
      )

    candidate_ids
    |> Enum.filter(fn position_id ->
      case PositionStore.get(
             db.store,
             position_id
           ) do
        {:ok, candidate} ->
          db.matcher.(position, candidate)

        :not_found ->
          false
      end
    end)
    |> MapSet.new()
  end
end
