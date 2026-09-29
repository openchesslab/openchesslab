defmodule GameDB.Storage.Disk.GameInsertRecovery do
  @moduledoc """
  Recovers one incomplete complete-game insert.

  CanonicalStore and OccurrenceStorage are expected to have completed
  their own component-level recovery before this recovery runs.

  If the canonical game was not published yet, the outer insert did not
  commit anything and the marker can be cleared.

  If the canonical game was published, its occurrences are rolled forward
  before the outer marker is cleared.
  """

  alias GameDB.Occurrence
  alias GameDB.Storage.Disk.CanonicalStore
  alias GameDB.Storage.Disk.GameInsertMarker
  alias GameDB.Storage.Disk.OccurrenceStorage

  @spec recover(
          Path.t(),
          CanonicalStore.t(),
          OccurrenceStorage.t()
        ) ::
          :ok
          | {:error, term()}
  def recover(directory, %CanonicalStore{} = canonical_store, %OccurrenceStorage{} = occurrence_storage)
      when is_binary(directory) do
    case GameInsertMarker.read(directory) do
      :none ->
        :ok

      {:ok,
       %{
         game_id: game_id,
         position_ids: position_ids
       }} ->
        recover_pending_insert(
          directory,
          canonical_store,
          occurrence_storage,
          game_id,
          position_ids
        )

      {:error, _reason} = error ->
        error
    end
  end

  defp recover_pending_insert(directory, canonical_store, occurrence_storage, game_id, position_ids) do
    case CanonicalStore.get(
           canonical_store,
           game_id
         ) do
      {:ok, _record} ->
        recover_published_game(
          directory,
          occurrence_storage,
          game_id,
          position_ids
        )

      :not_found ->
        recover_unpublished_game(
          directory,
          canonical_store,
          game_id
        )

      {:error, _reason} = error ->
        error
    end
  end

  defp recover_unpublished_game(directory, canonical_store, game_id) do
    with {:ok, game_count} <-
           CanonicalStore.cardinality(canonical_store) do
      expected_game_id =
        game_count + 1

      if game_id ==
           expected_game_id do
        GameInsertMarker.clear(directory)
      else
        {:error,
         {
           :unexpected_pending_game_id,
           game_id,
           expected_game_id
         }}
      end
    end
  end

  defp recover_published_game(directory, occurrence_storage, game_id, position_ids) do
    case OccurrenceStorage.occurrences(
           occurrence_storage,
           game_id
         ) do
      {:ok, occurrences} ->
        finish_existing_occurrences(
          directory,
          game_id,
          position_ids,
          occurrences
        )

      :not_found ->
        with :ok <-
               OccurrenceStorage.append(
                 occurrence_storage,
                 game_id,
                 position_ids
               ) do
          GameInsertMarker.clear(directory)
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp finish_existing_occurrences(directory, game_id, expected_position_ids, occurrences) do
    actual_position_ids =
      Enum.map(
        occurrences,
        fn %Occurrence{
             position_id: position_id
           } ->
          position_id
        end
      )

    if actual_position_ids ==
         expected_position_ids do
      GameInsertMarker.clear(directory)
    else
      {:error,
       {
         :game_occurrence_mismatch,
         game_id
       }}
    end
  end
end
