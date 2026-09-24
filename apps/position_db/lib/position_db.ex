defmodule PositionDB do
  alias PositionDB.EquivalenceContext
  alias PositionDB.PositionIndexer
  alias PositionDB.PositionStore
  alias PositionDB.PropertyIndex
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
    key_function =
      Keyword.fetch!(
        options,
        :key_function
      )

    properties =
      Keyword.fetch!(
        options,
        :properties
      )

    property_index =
      Keyword.get_lazy(
        options,
        :property_index,
        &PropertyIndex.new/0
      )

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

    store =
      case Keyword.fetch(
             options,
             :storage
           ) do
        {:ok, {storage_module, storage}} ->
          PositionStore.new(
            key_function,
            storage_module,
            storage
          )

        :error ->
          PositionStore.new(key_function)
      end

    %__MODULE__{
      store: store,
      indexer:
        PositionIndexer.new(
          properties,
          property_index
        ),
      equivalence:
        EquivalenceContext.new(
          equivalence_function,
          matcher
        )
    }
  end

  def append(db, position) do
    previous_cardinality =
      PositionStore.cardinality(db.store)

    case PositionStore.put(
           db.store,
           position
         ) do
      {:ok, store, position_id} ->
        if PositionStore.cardinality(store) ==
             previous_cardinality do
          {
            %{
              db
              | store: store
            },
            position_id
          }
        else
          index_new_position(
            db,
            store,
            position,
            position_id
          )
        end

      {:error, reason} ->
        {:error, reason}
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

  defp index_new_position(
         db,
         store,
         position,
         position_id
       ) do
    case PositionIndexer.index(
           db.indexer,
           position_id,
           position
         ) do
      %PositionIndexer{} = indexer ->
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

      {:error, reason} ->
        {:error, reason}
    end
  end
end
