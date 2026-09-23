defmodule PositionDB.Storage.Disk.ExactLookup do
  @moduledoc """
  Resolves exact-index candidates against stored position records.

  A matching index hash is not sufficient for exact identity.
  Candidate records are read and compared in full.
  """

  alias PositionDB.Storage.Disk.RecordStore

  @spec find(
          RecordStore.t(),
          module(),
          term(),
          binary(),
          binary()
        ) ::
          {:ok, pos_integer()}
          | :not_found
          | {:error, term()}
  def find(
        %RecordStore{} = record_store,
        index_module,
        index,
        key,
        expected_record
      )
      when is_atom(index_module) and
             is_binary(key) and
             is_binary(expected_record) do
    case index_module.lookup(
           index,
           key
         ) do
      {:ok, candidates} ->
        find_candidate(
          record_store,
          candidates,
          expected_record
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp find_candidate(
         _record_store,
         [],
         _expected_record
       ) do
    :not_found
  end

  defp find_candidate(
         record_store,
         [position_id | rest],
         expected_record
       ) do
    case RecordStore.get(
           record_store,
           position_id
         ) do
      {:ok, ^expected_record} ->
        {:ok, position_id}

      {:ok, _different_record} ->
        find_candidate(
          record_store,
          rest,
          expected_record
        )

      :not_found ->
        {:error, {:missing_position_record, position_id}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
