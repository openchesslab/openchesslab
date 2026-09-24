defmodule PositionDB.PropertyIndex.Disk.CatchUp do
  @moduledoc """
  Brings a persistent disk property index up to date with the
  committed positions in a PositionStore.

  The first position after the durable progress watermark is
  recovered rather than appended normally because it may have
  been interrupted after writing only part of its postings.

  Progress is advanced only after all postings for a position
  are durable.
  """

  alias PositionDB.PositionIndexer
  alias PositionDB.PositionStore
  alias PositionDB.PropertyIndex
  alias PositionDB.PropertyIndex.Disk

  @spec run(
          PositionStore.t(),
          PositionIndexer.t()
        ) ::
          {:ok, PositionIndexer.t()}
          | {:error, term()}
  def run(
        %PositionStore{} = store,
        %PositionIndexer{
          index: %PropertyIndex{
            backend_module: Disk
          }
        } = indexer
      ) do
    first_pending_id =
      Disk.indexed_through(indexer.index.backend) + 1

    last_committed_id =
      PositionStore.cardinality(store)

    catch_up_first(
      store,
      indexer,
      first_pending_id,
      last_committed_id
    )
  end

  defp catch_up_first(
         _store,
         indexer,
         position_id,
         last_committed_id
       )
       when position_id > last_committed_id do
    {:ok, indexer}
  end

  defp catch_up_first(
         store,
         indexer,
         position_id,
         last_committed_id
       ) do
    with {:ok, position} <-
           read_position(
             store,
             position_id
           ),
         {:ok, indexer} <-
           recover_position(
             indexer,
             position_id,
             position
           ) do
      catch_up_remaining(
        store,
        indexer,
        position_id + 1,
        last_committed_id
      )
    end
  end

  defp catch_up_remaining(
         _store,
         indexer,
         position_id,
         last_committed_id
       )
       when position_id > last_committed_id do
    {:ok, indexer}
  end

  defp catch_up_remaining(
         store,
         indexer,
         position_id,
         last_committed_id
       ) do
    with {:ok, position} <-
           read_position(
             store,
             position_id
           ),
         {:ok, indexer} <-
           index_position(
             indexer,
             position_id,
             position
           ) do
      catch_up_remaining(
        store,
        indexer,
        position_id + 1,
        last_committed_id
      )
    end
  end

  defp recover_position(
         indexer,
         position_id,
         position
       ) do
    properties =
      PositionIndexer.properties_for(
        indexer,
        position
      )

    with {:ok, indexer} <-
           recover_properties(
             indexer,
             properties,
             position_id
           ) do
      advance(
        indexer,
        position_id
      )
    end
  end

  defp recover_properties(
         indexer,
         [],
         _position_id
       ) do
    {:ok, indexer}
  end

  defp recover_properties(
         indexer,
         properties,
         position_id
       ) do
    case Disk.recover_adds(
           indexer.index.backend,
           properties,
           position_id
         ) do
      {:ok, backend} ->
        {:ok,
         put_backend(
           indexer,
           backend
         )}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp index_position(
         indexer,
         position_id,
         position
       ) do
    case PositionIndexer.index(
           indexer,
           position_id,
           position
         ) do
      %PositionIndexer{} = indexer ->
        {:ok, indexer}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp advance(
         indexer,
         position_id
       ) do
    case Disk.advance(
           indexer.index.backend,
           position_id
         ) do
      {:ok, backend} ->
        {:ok,
         put_backend(
           indexer,
           backend
         )}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp put_backend(
         indexer,
         backend
       ) do
    index =
      %{
        indexer.index
        | backend: backend
      }

    %{
      indexer
      | index: index
    }
  end

  defp read_position(
         store,
         position_id
       ) do
    case PositionStore.get(
           store,
           position_id
         ) do
      {:ok, position} ->
        {:ok, position}

      :not_found ->
        {:error, {:committed_position_not_found, position_id}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
