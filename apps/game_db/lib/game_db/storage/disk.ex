defmodule GameDB.Storage.Disk do
  @moduledoc """
  Disk-backed storage for canonical games and their position occurrences.

  The canonical store and occurrence storage are independently crash-safe.
  An outer game-insert marker coordinates recovery across both stores.
  """

  @behaviour GameDB.Storage

  alias GameDB.Storage
  alias GameDB.Storage.Disk.CanonicalStore
  alias GameDB.Storage.Disk.FingerprintFormat
  alias GameDB.Storage.Disk.GameInsertMarker
  alias GameDB.Storage.Disk.GameInsertRecovery
  alias GameDB.Storage.Disk.Manifest
  alias GameDB.Storage.Disk.ManifestStore
  alias GameDB.Storage.Disk.OccurrenceStorage

  @max_id 0xFFFF_FFFF_FFFF_FFFF
  @max_count 0xFFFF_FFFF

  @type t :: %__MODULE__{
          directory: Path.t(),
          canonical_store: CanonicalStore.t(),
          occurrence_storage: OccurrenceStorage.t(),
          game_count: non_neg_integer()
        }

  @type scan_state :: %{
          next_game_id: pos_integer(),
          last_game_id: non_neg_integer()
        }

  @enforce_keys [
    :directory,
    :canonical_store,
    :occurrence_storage,
    :game_count
  ]

  defstruct [
    :directory,
    :canonical_store,
    :occurrence_storage,
    :game_count
  ]

  @spec create(Path.t(), keyword()) ::
          {:ok, t()}
          | {:error, :storage_exists}
          | {:error, term()}
  def create(directory, opts) when is_binary(directory) do
    with {:ok, manifest} <- storage_manifest(opts),
         {:ok, _encoded} <- Manifest.encode(manifest) do
      case create_root_directory(directory) do
        :ok ->
          case create_components(
                 directory,
                 opts,
                 manifest
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
  end

  @spec open(Path.t(), keyword()) ::
          {:ok, t()}
          | {:error, term()}
  def open(directory, opts) when is_binary(directory) do
    codec =
      Keyword.fetch!(
        opts,
        :codec
      )

    fingerprint_format_id =
      Keyword.fetch!(
        opts,
        :fingerprint_format_id
      )

    fingerprint_size =
      Keyword.fetch!(
        opts,
        :fingerprint_size
      )

    with :ok <- validate_supported_fingerprint_size(fingerprint_size),
         {:ok, manifest} <- ManifestStore.read(directory),
         :ok <-
           validate_runtime_formats(
             manifest,
             codec,
             fingerprint_format_id,
             fingerprint_size
           ),
         {:ok, canonical_store} <-
           CanonicalStore.open(
             canonical_directory(directory),
             canonical_options(
               codec,
               manifest
             )
           ),
         {:ok, occurrence_storage} <-
           OccurrenceStorage.open(
             occurrence_directory(directory),
             occurrence_options(manifest)
           ),
         :ok <-
           GameInsertRecovery.recover(
             directory,
             canonical_store,
             occurrence_storage
           ),
         :ok <-
           GameInsertRecovery.recover(
             directory,
             canonical_store,
             occurrence_storage
           ),
         {:ok, canonical_game_count} <-
           CanonicalStore.cardinality(canonical_store),
         {:ok, occurrence_game_count} <-
           OccurrenceStorage.game_cardinality(occurrence_storage),
         :ok <-
           validate_game_counts(
             canonical_game_count,
             occurrence_game_count
           ) do
      {:ok,
       build_storage(
         directory,
         canonical_store,
         occurrence_storage,
         canonical_game_count
       )}
    end
  end

  @impl Storage
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

  @impl Storage
  def find(%__MODULE__{} = storage, fingerprint, record) do
    CanonicalStore.find(
      storage.canonical_store,
      fingerprint,
      record
    )
  end

  @impl Storage
  def get(%__MODULE__{} = storage, game_id) do
    CanonicalStore.get(
      storage.canonical_store,
      game_id
    )
  end

  @impl Storage
  def occurrences(%__MODULE__{} = storage, game_id) do
    OccurrenceStorage.occurrences(
      storage.occurrence_storage,
      game_id
    )
  end

  @impl Storage
  def occurrences_by_position_id(%__MODULE__{} = storage, position_id) do
    storage
    |> scan_occurrences(position_id)
    |> collect_occurrences([])
  end

  @impl Storage
  def scan_occurrences(%__MODULE__{} = storage, position_id) do
    OccurrenceStorage.scan(
      storage.occurrence_storage,
      position_id
    )
  end

  @impl Storage
  def scan_occurrences_next(scan) do
    OccurrenceStorage.scan_next(scan)
  end

  @impl Storage
  def get_occurrence(%__MODULE__{} = storage, occurrence_id) do
    OccurrenceStorage.get_occurrence(
      storage.occurrence_storage,
      occurrence_id
    )
  end

  @impl Storage
  def cardinality(%__MODULE__{game_count: game_count}) do
    game_count
  end

  @impl Storage
  def scan(%__MODULE__{game_count: game_count}) do
    %{
      next_game_id: 1,
      last_game_id: game_count
    }
  end

  @impl Storage
  def scan_next(%{next_game_id: next_game_id, last_game_id: last_game_id} = scan)
      when next_game_id <= last_game_id do
    {:ok, next_game_id, %{scan | next_game_id: next_game_id + 1}}
  end

  def scan_next(%{next_game_id: next_game_id, last_game_id: last_game_id})
      when next_game_id > last_game_id do
    :done
  end

  defp create_components(directory, opts, %Manifest{} = manifest) do
    codec =
      Keyword.fetch!(
        opts,
        :codec
      )

    with {:ok, canonical_store} <-
           CanonicalStore.create(
             canonical_directory(directory),
             canonical_options(
               codec,
               manifest
             )
           ),
         {:ok, occurrence_storage} <-
           OccurrenceStorage.create(
             occurrence_directory(directory),
             occurrence_options(manifest)
           ),
         :ok <-
           ManifestStore.create(
             directory,
             manifest
           ) do
      {:ok,
       build_storage(
         directory,
         canonical_store,
         occurrence_storage,
         0
       )}
    end
  end

  defp build_storage(directory, canonical_store, occurrence_storage, game_count) do
    %__MODULE__{
      directory: directory,
      canonical_store: canonical_store,
      occurrence_storage: occurrence_storage,
      game_count: game_count
    }
  end

  defp canonical_options(codec, %Manifest{} = manifest) do
    [
      codec: codec,
      bucket_count: manifest.canonical_bucket_count
    ]
  end

  defp occurrence_options(%Manifest{} = manifest) do
    [
      position_bucket_count: manifest.position_bucket_count
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
    game_id = storage.game_count + 1

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
      {:ok,
       %{
         storage
         | canonical_store: canonical_store,
           game_count: game_id
       }, game_id}
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

  defp collect_occurrences(scan, reversed) do
    case OccurrenceStorage.scan_next(scan) do
      {:ok, occurrence, scan} ->
        collect_occurrences(
          scan,
          [occurrence | reversed]
        )

      :done ->
        {:ok, Enum.reverse(reversed)}

      {:error, _reason} = error ->
        error
    end
  end

  defp storage_manifest(opts) do
    codec =
      Keyword.fetch!(
        opts,
        :codec
      )

    fingerprint_format_id =
      Keyword.fetch!(
        opts,
        :fingerprint_format_id
      )

    fingerprint_size =
      Keyword.fetch!(
        opts,
        :fingerprint_size
      )

    canonical_bucket_count =
      Keyword.fetch!(
        opts,
        :bucket_count
      )

    position_bucket_count =
      Keyword.fetch!(
        opts,
        :position_bucket_count
      )

    with :ok <- validate_supported_fingerprint_size(fingerprint_size) do
      {:ok,
       %Manifest{
         record_format_id: codec.format_id(),
         fingerprint_format_id: fingerprint_format_id,
         fingerprint_size: fingerprint_size,
         canonical_bucket_count: canonical_bucket_count,
         position_bucket_count: position_bucket_count
       }}
    end
  end

  defp validate_runtime_formats(
         %Manifest{} = manifest,
         codec,
         fingerprint_format_id,
         fingerprint_size
       ) do
    with :ok <-
           validate_format_value(
             :record_format_id,
             manifest.record_format_id,
             codec.format_id()
           ),
         :ok <-
           validate_format_value(
             :fingerprint_format_id,
             manifest.fingerprint_format_id,
             fingerprint_format_id
           ) do
      validate_format_value(
        :fingerprint_size,
        manifest.fingerprint_size,
        fingerprint_size
      )
    end
  end

  defp validate_format_value(_field, value, value) do
    :ok
  end

  defp validate_format_value(field, persisted, configured) do
    {:error,
     {
       :storage_format_mismatch,
       field,
       persisted,
       configured
     }}
  end

  defp validate_supported_fingerprint_size(fingerprint_size) do
    if fingerprint_size == FingerprintFormat.size() do
      :ok
    else
      {:error,
       {
         :unsupported_fingerprint_size,
         fingerprint_size
       }}
    end
  end

  defp validate_game_counts(game_count, game_count) do
    :ok
  end

  defp validate_game_counts(canonical_game_count, occurrence_game_count) do
    {:error,
     {
       :game_count_mismatch,
       canonical_game_count,
       occurrence_game_count
     }}
  end
end
