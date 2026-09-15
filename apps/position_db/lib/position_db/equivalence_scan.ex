defmodule PositionDB.EquivalenceScan do
  @moduledoc """
  Lazily scans positions that are candidates for equivalence with a query
  position and filters them using the configured matcher.
  """

  alias PositionDB.EquivalenceIndex
  alias PositionDB.PositionStore
  alias PositionDB.QueryExecutor

  @type position_id :: non_neg_integer()
  @type equivalence_key :: term()
  @type equivalence_function :: (term() -> equivalence_key())
  @type matcher :: (term(), term() -> boolean())

  @spec new(
          EquivalenceIndex.t(),
          PositionStore.t(),
          equivalence_function(),
          matcher(),
          term()
        ) :: QueryExecutor.t()
  def new(
        equivalence_index,
        store,
        equivalence_function,
        matcher,
        position
      ) do
    key = equivalence_function.(position)

    candidate_ids =
      equivalence_index
      |> EquivalenceIndex.lookup(key)
      |> Enum.sort()

    QueryExecutor.new(
      __MODULE__,
      %{
        candidate_ids: candidate_ids,
        store: store,
        matcher: matcher,
        position: position
      }
    )
  end

  @spec next(map()) ::
          {:ok, position_id(), map()}
          | :done
  def next(%{candidate_ids: []}) do
    :done
  end

  def next(
        %{
          candidate_ids: [position_id | rest],
          store: store,
          matcher: matcher,
          position: position
        } = state
      ) do
    case PositionStore.get(store, position_id) do
      {:ok, candidate} ->
        if matcher.(position, candidate) do
          {:ok, position_id, %{state | candidate_ids: rest}}
        else
          next(%{state | candidate_ids: rest})
        end

      :not_found ->
        next(%{state | candidate_ids: rest})
    end
  end
end
