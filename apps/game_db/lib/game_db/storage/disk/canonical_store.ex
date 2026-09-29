defmodule GameDB.Storage.Disk.CanonicalStore do
  @moduledoc """
  Crash-safe disk storage for canonical games.

  Canonical game records are authoritative. The fingerprint index is a
  rebuildable secondary index.

  A new game is persisted in this order:

    1. create the append marker
    2. append the authoritative game record
    3. append the fingerprint index entry
    4. clear the append marker

  On reopen, an unfinished append is recovered before the store is returned.
  """

  alias GameDB.Storage.Disk.AppendMarker
  alias GameDB.Storage.Disk.FingerprintIndex
  alias GameDB.Storage.Disk.GameRecordStore
  alias GameDB.Storage.Disk.RecordStore

  @type t :: %__MODULE__{
          directory: Path.t(),
          game_records: GameRecordStore.t(),
          fingerprint_index: FingerprintIndex.t()
        }

  @type scan_state :: %{
          next_id: pos_integer(),
          last_id: non_neg_integer()
        }

  @enforce_keys [
    :directory,
    :game_records,
    :fingerprint_index
  ]

  defstruct [
    :directory,
    :game_records,
    :fingerprint_index
  ]

  @spec create(Path.t(), keyword()) ::
          {:ok, t()}
          | {:error, :storage_exists}
          | {:error, term()}
  def create(directory, opts) when is_binary(directory) do
    {codec, bucket_count} =
      storage_options(opts)

    case create_root_directory(directory) do
      :ok ->
        case create_storage_directories(directory) do
          {:ok, record_store} ->
            {:ok,
             build_store(
               directory,
               record_store,
               codec,
               bucket_count
             )}

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
    {codec, bucket_count} =
      storage_options(opts)

    with :ok <-
           validate_directory(directory),
         :ok <-
           validate_directory(fingerprint_index_directory(directory)),
         {:ok, record_store} <-
           RecordStore.open(games_directory(directory)) do
      store =
        build_store(
          directory,
          record_store,
          codec,
          bucket_count
        )

      with :ok <-
             recover_pending_append(store) do
        {:ok, store}
      end
    end
  end

  @spec put(
          t(),
          binary(),
          term()
        ) ::
          {:ok, t(), pos_integer()}
          | {:error, term()}
  def put(%__MODULE__{} = store, fingerprint, record) when is_binary(fingerprint) do
    with :ok <-
           ensure_no_pending_append(store) do
      case find(
             store,
             fingerprint,
             record
           ) do
        {:ok, game_id} ->
          {:ok, store, game_id}

        :not_found ->
          append_new_game(
            store,
            fingerprint,
            record
          )

        {:error, _reason} = error ->
          error
      end
    end
  end

  def put(%__MODULE__{}, _fingerprint, _record) do
    {:error, :invalid_fingerprint}
  end

  @spec find(
          t(),
          binary(),
          term()
        ) ::
          {:ok, pos_integer()}
          | :not_found
          | {:error, term()}
  def find(%__MODULE__{} = store, fingerprint, record) when is_binary(fingerprint) do
    with {:ok, candidates} <-
           FingerprintIndex.lookup(
             store.fingerprint_index,
             fingerprint
           ) do
      find_candidate(
        store,
        candidates,
        record
      )
    end
  end

  def find(%__MODULE__{}, _fingerprint, _record) do
    {:error, :invalid_fingerprint}
  end

  @spec get(
          t(),
          pos_integer()
        ) ::
          {:ok, term()}
          | :not_found
          | {:error, term()}
  def get(%__MODULE__{} = store, game_id) do
    GameRecordStore.get(
      store.game_records,
      game_id
    )
  end

  @spec cardinality(t()) ::
          {:ok, non_neg_integer()}
          | {:error, term()}
  def cardinality(%__MODULE__{} = store) do
    GameRecordStore.cardinality(store.game_records)
  end

  @spec scan(t()) ::
          {:ok, scan_state()}
          | {:error, term()}
  def scan(%__MODULE__{} = store) do
    case cardinality(store) do
      {:ok, count} ->
        {:ok,
         %{
           next_id: 1,
           last_id: count
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec scan_next(scan_state()) ::
          {:ok, pos_integer(), scan_state()}
          | :done
  def scan_next(%{next_id: next_id, last_id: last_id} = state) when next_id <= last_id do
    {:ok, next_id,
     %{
       state
       | next_id: next_id + 1
     }}
  end

  def scan_next(%{next_id: next_id, last_id: last_id}) when next_id > last_id do
    :done
  end

  defp storage_options(opts) do
    codec =
      Keyword.fetch!(
        opts,
        :codec
      )

    bucket_count =
      Keyword.fetch!(
        opts,
        :bucket_count
      )

    if !is_atom(codec) do
      raise ArgumentError,
            "codec must be a module"
    end

    if !(is_integer(bucket_count) and
           bucket_count > 0) do
      raise ArgumentError,
            "bucket_count must be positive"
    end

    {
      codec,
      bucket_count
    }
  end

  defp build_store(directory, record_store, codec, bucket_count) do
    %__MODULE__{
      directory: directory,
      game_records:
        GameRecordStore.new(
          record_store,
          codec
        ),
      fingerprint_index:
        FingerprintIndex.new(
          fingerprint_index_directory(directory),
          bucket_count: bucket_count
        )
    }
  end

  defp find_candidate(_store, [], _record) do
    :not_found
  end

  defp find_candidate(store, [game_id | remaining], record) do
    case GameRecordStore.get(
           store.game_records,
           game_id
         ) do
      {:ok, stored_record} ->
        if stored_record == record do
          {:ok, game_id}
        else
          find_candidate(
            store,
            remaining,
            record
          )
        end

      :not_found ->
        {:error,
         {
           :missing_game_record,
           game_id
         }}

      {:error, _reason} = error ->
        error
    end
  end

  defp append_new_game(store, fingerprint, record) do
    with {:ok, count} <-
           cardinality(store) do
      game_id =
        count + 1

      with :ok <-
             AppendMarker.create(
               store.directory,
               game_id
             ),
           :ok <-
             append_expected_record(
               store,
               game_id,
               fingerprint,
               record
             ),
           {:ok, fingerprint_index} <-
             FingerprintIndex.add(
               store.fingerprint_index,
               fingerprint,
               game_id
             ),
           :ok <-
             AppendMarker.clear(store.directory) do
        {:ok,
         %{
           store
           | fingerprint_index: fingerprint_index
         }, game_id}
      end
    end
  end

  defp append_expected_record(store, expected_game_id, fingerprint, record) do
    case GameRecordStore.append(
           store.game_records,
           fingerprint,
           record
         ) do
      {:ok, ^expected_game_id} ->
        :ok

      {:ok, actual_game_id} ->
        {:error,
         {
           :unexpected_game_id,
           expected_game_id,
           actual_game_id
         }}

      {:error, _reason} = error ->
        error
    end
  end

  defp recover_pending_append(%__MODULE__{} = store) do
    case AppendMarker.read(store.directory) do
      :none ->
        :ok

      {:ok, game_id} ->
        recover_pending_append(
          store,
          game_id
        )

      {:error, _reason} = error ->
        error
    end
  end

  defp recover_pending_append(store, game_id) do
    case GameRecordStore.fingerprint(
           store.game_records,
           game_id
         ) do
      {:ok, fingerprint} ->
        with :ok <-
               FingerprintIndex.recover_pending_append(
                 store.fingerprint_index,
                 fingerprint,
                 game_id
               ) do
          AppendMarker.clear(store.directory)
        end

      :not_found ->
        recover_missing_record(
          store,
          game_id
        )

      {:error, _reason} = error ->
        error
    end
  end

  defp recover_missing_record(store, game_id) do
    with {:ok, count} <-
           cardinality(store) do
      expected_game_id =
        count + 1

      if game_id ==
           expected_game_id do
        AppendMarker.clear(store.directory)
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

  defp ensure_no_pending_append(%__MODULE__{} = store) do
    case AppendMarker.read(store.directory) do
      :none ->
        :ok

      {:ok, game_id} ->
        {:error,
         {
           :incomplete_append,
           game_id
         }}

      {:error, _reason} = error ->
        error
    end
  end

  defp create_storage_directories(directory) do
    with {:ok, record_store} <-
           RecordStore.create(games_directory(directory)),
         :ok <-
           create_directory(fingerprint_index_directory(directory)) do
      {:ok, record_store}
    end
  end

  defp create_root_directory(directory) do
    with :ok <-
           File.mkdir(directory) do
      sync_directory(Path.dirname(directory))
    end
  end

  defp create_directory(directory) do
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

  defp games_directory(directory) do
    Path.join(
      directory,
      "games"
    )
  end

  defp fingerprint_index_directory(directory) do
    Path.join(
      directory,
      "fingerprint-index"
    )
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
