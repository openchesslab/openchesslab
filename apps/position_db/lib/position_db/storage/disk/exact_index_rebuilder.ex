defmodule PositionDB.Storage.Disk.ExactIndexRebuilder do
  @moduledoc """
  Rebuilds and replaces the disk exact index from durable records.

  A replacement is first built completely in a sibling directory.
  Once durable, the active index is moved to a backup and the
  replacement is promoted.

  Interrupted replacement states can be recovered with `recover/1`.
  """

  alias PositionDB.Storage.Disk.Durability
  alias PositionDB.Storage.Disk.ExactIndexBuilder
  alias PositionDB.Storage.Disk.RecordStore
  alias PositionDB.Storage.ExactIndex.Disk, as: ExactIndex

  @spec rebuild(
          RecordStore.t(),
          ExactIndex.t()
        ) ::
          {:ok, ExactIndex.t()}
          | {:error, term()}
  def rebuild(
        %RecordStore{} = record_store,
        %ExactIndex{} = exact_index
      ) do
    active =
      exact_index.bucket_store.directory

    rebuild =
      rebuild_directory(active)

    backup =
      backup_directory(active)

    with :ok <-
           recover(active),
         :ok <-
           ensure_directory(active),
         :ok <-
           Durability.create_directory(rebuild),
         :ok <-
           build_replacement(
             record_store,
             exact_index,
             rebuild
           ),
         :ok <-
           replace(
             active,
             rebuild,
             backup
           ) do
      {:ok, exact_index}
    end
  end

  @spec recover(Path.t()) ::
          :ok
          | {:error, term()}
  def recover(active)
      when is_binary(active) do
    rebuild =
      rebuild_directory(active)

    backup =
      backup_directory(active)

    with {:ok, active?} <-
           directory_state(active),
         {:ok, rebuild?} <-
           directory_state(rebuild),
         {:ok, backup?} <-
           directory_state(backup) do
      recover_state(
        active?,
        rebuild?,
        backup?,
        active,
        rebuild,
        backup
      )
    end
  end

  defp build_replacement(
         record_store,
         exact_index,
         rebuild
       ) do
    replacement =
      ExactIndex.new(
        rebuild,
        bucket_count: exact_index.bucket_count,
        hash: exact_index.hash_module
      )

    case ExactIndexBuilder.build(
           record_store,
           replacement
         ) do
      {:ok, _replacement} ->
        :ok

      {:error, reason} ->
        case Durability.remove_directory(rebuild) do
          :ok ->
            {:error, reason}

          {:error, cleanup_reason} ->
            {:error, {:exact_index_rebuild_failed, reason, cleanup_reason}}
        end
    end
  end

  defp replace(
         active,
         rebuild,
         backup
       ) do
    with :ok <-
           Durability.rename_sibling(
             active,
             backup
           ),
         :ok <-
           Durability.rename_sibling(
             rebuild,
             active
           ),
         :ok <-
           Durability.remove_directory(backup) do
      :ok
    else
      {:error, reason} ->
        case recover(active) do
          :ok ->
            {:error, {:exact_index_replace_failed, reason}}

          {:error, recovery_reason} ->
            {:error, {:exact_index_replace_failed, reason, recovery_reason}}
        end
    end
  end

  defp recover_state(
         true,
         false,
         false,
         _active,
         _rebuild,
         _backup
       ) do
    :ok
  end

  # Build was interrupted before the active index was touched.
  defp recover_state(
         true,
         true,
         false,
         _active,
         rebuild,
         _backup
       ) do
    Durability.remove_directory(rebuild)
  end

  # Replacement was promoted; backup cleanup was interrupted.
  defp recover_state(
         true,
         false,
         true,
         _active,
         _rebuild,
         backup
       ) do
    Durability.remove_directory(backup)
  end

  # Active was moved aside after a completed durable rebuild.
  defp recover_state(
         false,
         true,
         true,
         active,
         rebuild,
         backup
       ) do
    with :ok <-
           Durability.rename_sibling(
             rebuild,
             active
           ),
         :ok <-
           Durability.remove_directory(backup) do
      :ok
    end
  end

  # Rebuild disappeared after the active index was moved.
  # Restore the known-good backup.
  defp recover_state(
         false,
         false,
         true,
         active,
         _rebuild,
         backup
       ) do
    Durability.rename_sibling(
      backup,
      active
    )
  end

  # Nothing exists. Disk.open/2 will subsequently report the
  # missing active exact-index directory using its existing error.
  defp recover_state(
         false,
         false,
         false,
         _active,
         _rebuild,
         _backup
       ) do
    :ok
  end

  defp recover_state(
         _active?,
         _rebuild?,
         _backup?,
         _active,
         _rebuild,
         _backup
       ) do
    {:error, :ambiguous_exact_index_recovery}
  end

  defp directory_state(path) do
    case File.stat(path) do
      {:ok, %{type: :directory}} ->
        {:ok, true}

      {:ok, _stat} ->
        {:error, {:invalid_exact_index_path, path}}

      {:error, :enoent} ->
        {:ok, false}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ensure_directory(path) do
    case directory_state(path) do
      {:ok, true} ->
        :ok

      {:ok, false} ->
        {:error, :missing_exact_index_directory}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp rebuild_directory(active) do
    active <>
      ".rebuild"
  end

  defp backup_directory(active) do
    active <>
      ".backup"
  end
end
