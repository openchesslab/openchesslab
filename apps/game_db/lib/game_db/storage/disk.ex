defmodule GameDB.Storage.Disk do
  @moduledoc """
  Disk-backed storage for canonical games and their position occurrences.

  The canonical store and occurrence storage are independently crash-safe.
  An outer game-insert marker coordinates recovery across both stores.
  """

  alias GameDB.Storage.Disk.CanonicalStore
  alias GameDB.Storage.Disk.GameInsertRecovery
  alias GameDB.Storage.Disk.OccurrenceStorage

  @type t :: %__MODULE__{
          directory: Path.t(),
          canonical_store: CanonicalStore.t(),
          occurrence_storage: OccurrenceStorage.t()
        }

  @enforce_keys [
    :directory,
    :canonical_store,
    :occurrence_storage
  ]

  defstruct [
    :directory,
    :canonical_store,
    :occurrence_storage
  ]

  @spec create(Path.t(), keyword()) ::
          {:ok, t()}
          | {:error, :storage_exists}
          | {:error, term()}
  def create(directory, opts) when is_binary(directory) do
    case create_root_directory(directory) do
      :ok ->
        case create_components(
               directory,
               opts
             ) do
          {:ok, storage} ->
            {:ok, storage}

          {:error, reason} ->
            cleanup_failed_create(directory)

            {:error, reason}
        end

      {:error, :eexist} ->
        {:error, :storage_exists}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec open(Path.t(), keyword()) ::
          {:ok, t()}
          | {:error, term()}
  def open(directory, opts) when is_binary(directory) do
    with :ok <-
           validate_directory(directory),
         {:ok, canonical_store} <-
           CanonicalStore.open(
             canonical_directory(directory),
             canonical_options(opts)
           ),
         {:ok, occurrence_storage} <-
           OccurrenceStorage.open(
             occurrence_directory(directory),
             occurrence_options(opts)
           ),
         :ok <-
           GameInsertRecovery.recover(
             directory,
             canonical_store,
             occurrence_storage
           ) do
      {:ok,
       build_storage(
         directory,
         canonical_store,
         occurrence_storage
       )}
    end
  end

  defp create_components(directory, opts) do
    with {:ok, canonical_store} <-
           CanonicalStore.create(
             canonical_directory(directory),
             canonical_options(opts)
           ),
         {:ok, occurrence_storage} <-
           OccurrenceStorage.create(
             occurrence_directory(directory),
             occurrence_options(opts)
           ) do
      {:ok,
       build_storage(
         directory,
         canonical_store,
         occurrence_storage
       )}
    end
  end

  defp build_storage(directory, canonical_store, occurrence_storage) do
    %__MODULE__{
      directory: directory,
      canonical_store: canonical_store,
      occurrence_storage: occurrence_storage
    }
  end

  defp canonical_options(opts) do
    [
      codec:
        Keyword.fetch!(
          opts,
          :codec
        ),
      bucket_count:
        Keyword.fetch!(
          opts,
          :bucket_count
        )
    ]
  end

  defp occurrence_options(opts) do
    [
      position_bucket_count:
        Keyword.fetch!(
          opts,
          :position_bucket_count
        )
    ]
  end

  defp canonical_directory(directory) do
    Path.join(
      directory,
      "canonical"
    )
  end

  defp occurrence_directory(directory) do
    Path.join(
      directory,
      "occurrences"
    )
  end

  defp create_root_directory(directory) do
    with :ok <-
           File.mkdir(directory) do
      sync_directory(Path.dirname(directory))
    end
  end

  defp validate_directory(directory) do
    case File.stat(directory) do
      {:ok, %{type: :directory}} ->
        :ok

      {:ok, _stat} ->
        {:error, :not_a_directory}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp cleanup_failed_create(directory) do
    File.rm_rf(directory)

    :ok
  end

  defp sync_directory(directory) do
    case :os.type() do
      {:unix, _name} ->
        case :file.open(
               directory,
               [
                 :read,
                 :directory
               ]
             ) do
          {:ok, file} ->
            try do
              :file.sync(file)
            after
              :file.close(file)
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:win32, _name} ->
        :ok
    end
  end
end
