defmodule GameDB.Storage.Disk do
  @moduledoc """
  Disk-backed storage for canonical games and their position occurrences.

  The canonical store and occurrence storage are independently crash-safe.
  An outer game-insert marker coordinates recovery across both stores.
  """

  alias GameDB.Storage.Disk.CanonicalStore
  alias GameDB.Storage.Disk.GameInsertMarker
  alias GameDB.Storage.Disk.GameInsertRecovery
  alias GameDB.Storage.Disk.OccurrenceStorage

  @max_id 0xFFFF_FFFF_FFFF_FFFF
  @max_count 0xFFFF_FFFF

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

  @spec put(
          t(),
          binary(),
          term(),
          [pos_integer()]
        ) ::
          {:ok, t(), pos_integer()}
          | {:error, term()}
  def put(%__MODULE__{} = storage, fingerprint, record, position_ids)
      when is_binary(fingerprint) and is_list(position_ids) do
    with :ok <- ensure_no_pending_insert(storage),
         :ok <- validate_position_ids(position_ids) do
      case CanonicalStore.find(
             storage.canonical_store,
             fingerprint,
             record
           ) do
        {:ok, game_id} ->
          {:ok, storage, game_id}

        :not_found ->
          append_new_game(
            storage,
            fingerprint,
            record,
            position_ids
          )

        {:error, _reason} = error ->
          error
      end
    end
  end

  def put(%__MODULE__{}, fingerprint, _record, _position_ids) when not is_binary(fingerprint) do
    {:error, :invalid_fingerprint}
  end

  def put(%__MODULE__{}, _fingerprint, _record, _position_ids) do
    {:error, :invalid_position_ids}
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

  defp append_new_game(storage, fingerprint, record, position_ids) do
    with {:ok, game_count} <- CanonicalStore.cardinality(storage.canonical_store) do
      game_id = game_count + 1

      with :ok <-
             GameInsertMarker.create(
               storage.directory,
               game_id,
               position_ids
             ),
           {:ok, canonical_store} <-
             put_expected_canonical_game(
               storage.canonical_store,
               game_id,
               fingerprint,
               record
             ),
           :ok <-
             OccurrenceStorage.append(
               storage.occurrence_storage,
               game_id,
               position_ids
             ),
           :ok <- GameInsertMarker.clear(storage.directory) do
        {:ok, %{storage | canonical_store: canonical_store}, game_id}
      end
    end
  end

  defp put_expected_canonical_game(canonical_store, expected_game_id, fingerprint, record) do
    case CanonicalStore.put(
           canonical_store,
           fingerprint,
           record
         ) do
      {:ok, canonical_store, ^expected_game_id} ->
        {:ok, canonical_store}

      {:ok, _canonical_store, actual_game_id} ->
        {:error, {:unexpected_game_id, expected_game_id, actual_game_id}}

      {:error, _reason} = error ->
        error
    end
  end

  defp ensure_no_pending_insert(%__MODULE__{} = storage) do
    case GameInsertMarker.read(storage.directory) do
      :none ->
        :ok

      {:ok, %{game_id: game_id}} ->
        {:error, {:incomplete_game_insert, game_id}}

      {:error, _reason} = error ->
        error
    end
  end

  defp validate_position_ids([]) do
    {:error, :missing_initial_position}
  end

  defp validate_position_ids(position_ids) when is_list(position_ids) do
    cond do
      length(position_ids) > @max_count ->
        {:error, :too_many_occurrences}

      Enum.all?(
        position_ids,
        &(is_integer(&1) and &1 > 0 and &1 <= @max_id)
      ) ->
        :ok

      true ->
        {:error, :invalid_position_ids}
    end
  end
end
