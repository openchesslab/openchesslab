defmodule GameDB.Storage.Disk.OccurrenceStorage do
  @moduledoc """
  Crash-safe disk storage for game position occurrences.

  Occurrence records are authoritative. Two secondary indexes provide:

    * game ID -> contiguous occurrence span
    * position ID -> occurrence IDs

  One logical append is persisted in this order:

    1. create the recovery marker
    2. append occurrence records
    3. append the game occurrence span
    4. append position occurrence postings
    5. clear the recovery marker

  On reopen, an unfinished append is rolled forward before the storage
  is returned.
  """

  alias GameDB.Occurrence
  alias GameDB.Storage.Disk.GameOccurrenceIndex
  alias GameDB.Storage.Disk.OccurrenceAppendMarker
  alias GameDB.Storage.Disk.OccurrenceStore
  alias GameDB.Storage.Disk.PositionOccurrenceIndex

  @type t :: %__MODULE__{
          directory: Path.t(),
          occurrence_store: OccurrenceStore.t(),
          game_index: GameOccurrenceIndex.t(),
          position_index: PositionOccurrenceIndex.t()
        }

  @type scan_state :: %{
          occurrence_store: OccurrenceStore.t(),
          position_id: pos_integer(),
          position_scan: PositionOccurrenceIndex.scan_state()
        }

  @enforce_keys [
    :directory,
    :occurrence_store,
    :game_index,
    :position_index
  ]

  defstruct [
    :directory,
    :occurrence_store,
    :game_index,
    :position_index
  ]

  @spec create(Path.t(), keyword()) ::
          {:ok, t()}
          | {:error, :storage_exists}
          | {:error, term()}
  def create(directory, opts)
      when is_binary(directory) do
    position_bucket_count =
      position_bucket_count(opts)

    case create_root_directory(directory) do
      :ok ->
        case create_components(
               directory,
               position_bucket_count
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
  def open(directory, opts)
      when is_binary(directory) do
    position_bucket_count =
      position_bucket_count(opts)

    with :ok <-
           validate_directory(directory),
         {:ok, occurrence_store} <-
           OccurrenceStore.open(occurrence_records_directory(directory)),
         {:ok, game_index} <-
           GameOccurrenceIndex.open(game_index_directory(directory)),
         :ok <-
           validate_directory(position_index_directory(directory)) do
      storage =
        build_storage(
          directory,
          occurrence_store,
          game_index,
          position_bucket_count
        )

      with :ok <-
             recover_pending_append(storage),
           :ok <-
             validate_open_storage(storage) do
        {:ok, storage}
      end
    end
  end

  @spec append(
          t(),
          pos_integer(),
          [pos_integer()]
        ) ::
          :ok
          | {:error, term()}
  def append(
        %__MODULE__{} = storage,
        game_id,
        position_ids
      )
      when is_integer(game_id) and
             game_id > 0 and
             is_list(position_ids) do
    with :ok <-
           ensure_no_pending_append(storage),
         :ok <-
           validate_expected_game_id(
             storage,
             game_id
           ),
         {:ok, occurrence_count} <-
           OccurrenceStore.cardinality(storage.occurrence_store) do
      first_occurrence_id =
        occurrence_count + 1

      persist_batch(
        storage,
        game_id,
        first_occurrence_id,
        position_ids
      )
    end
  end

  def append(
        %__MODULE__{},
        game_id,
        _position_ids
      )
      when not is_integer(game_id) or
             game_id <= 0 do
    {:error, :invalid_game_id}
  end

  def append(
        %__MODULE__{},
        _game_id,
        _position_ids
      ) do
    {:error, :invalid_position_ids}
  end

  @spec occurrences(
          t(),
          pos_integer()
        ) ::
          {:ok, [Occurrence.t()]}
          | :not_found
          | {:error, term()}
  def occurrences(
        %__MODULE__{} = storage,
        game_id
      )
      when is_integer(game_id) and
             game_id > 0 do
    case GameOccurrenceIndex.get(
           storage.game_index,
           game_id
         ) do
      {:ok,
       {
         first_occurrence_id,
         occurrence_count
       }} ->
        read_game_occurrences(
          storage,
          game_id,
          first_occurrence_id,
          occurrence_count
        )

      :not_found ->
        :not_found

      {:error, _reason} = error ->
        error
    end
  end

  @spec get_occurrence(
          t(),
          pos_integer()
        ) ::
          {:ok, Occurrence.t()}
          | :not_found
          | {:error, term()}
  def get_occurrence(
        %__MODULE__{} = storage,
        occurrence_id
      ) do
    OccurrenceStore.get(
      storage.occurrence_store,
      occurrence_id
    )
  end

  @spec scan(
          t(),
          pos_integer()
        ) ::
          scan_state()
  def scan(
        %__MODULE__{} = storage,
        position_id
      )
      when is_integer(position_id) and
             position_id > 0 do
    %{
      occurrence_store: storage.occurrence_store,
      position_id: position_id,
      position_scan:
        PositionOccurrenceIndex.scan(
          storage.position_index,
          position_id
        )
    }
  end

  @spec scan_next(scan_state()) ::
          {:ok, Occurrence.t(), scan_state()}
          | :done
          | {:error, term()}
  def scan_next(
        %{
          occurrence_store: occurrence_store,
          position_id: position_id,
          position_scan: position_scan
        } = state
      ) do
    case PositionOccurrenceIndex.scan_next(position_scan) do
      {
        :ok,
        occurrence_id,
        position_scan
      } ->
        case OccurrenceStore.get(
               occurrence_store,
               occurrence_id
             ) do
          {:ok,
           %Occurrence{
             position_id: ^position_id
           } = occurrence} ->
            {:ok, occurrence,
             %{
               state
               | position_scan: position_scan
             }}

          {:ok, %Occurrence{}} ->
            {:error,
             {
               :invalid_position_occurrence,
               occurrence_id
             }}

          :not_found ->
            {:error,
             {
               :missing_occurrence,
               occurrence_id
             }}

          {:error, _reason} = error ->
            error
        end

      :done ->
        :done

      {:error, _reason} = error ->
        error
    end
  end

  defp persist_batch(
         storage,
         game_id,
         first_occurrence_id,
         position_ids
       ) do
    occurrence_count =
      length(position_ids)

    with :ok <-
           OccurrenceAppendMarker.create(
             storage.directory,
             game_id,
             first_occurrence_id,
             position_ids
           ),
         :ok <-
           append_expected_occurrences(
             storage,
             game_id,
             first_occurrence_id,
             occurrence_count,
             position_ids
           ),
         :ok <-
           GameOccurrenceIndex.append(
             storage.game_index,
             game_id,
             first_occurrence_id,
             occurrence_count
           ),
         {:ok, _position_index} <-
           PositionOccurrenceIndex.add_all(
             storage.position_index,
             position_postings(
               position_ids,
               first_occurrence_id
             )
           ),
         :ok <-
           OccurrenceAppendMarker.clear(storage.directory) do
      :ok
    end
  end

  defp append_expected_occurrences(
         storage,
         game_id,
         expected_first_occurrence_id,
         expected_count,
         position_ids
       ) do
    case OccurrenceStore.append(
           storage.occurrence_store,
           game_id,
           position_ids
         ) do
      {:ok, ^expected_first_occurrence_id, ^expected_count} ->
        :ok

      {:ok, actual_first_occurrence_id, actual_count} ->
        {:error,
         {
           :unexpected_occurrence_span,
           {
             expected_first_occurrence_id,
             expected_count
           },
           {
             actual_first_occurrence_id,
             actual_count
           }
         }}

      {:error, _reason} = error ->
        error
    end
  end

  defp validate_expected_game_id(
         storage,
         game_id
       ) do
    with {:ok, game_count} <-
           GameOccurrenceIndex.cardinality(storage.game_index) do
      expected_game_id =
        game_count + 1

      if game_id ==
           expected_game_id do
        :ok
      else
        {:error,
         {
           :unexpected_game_id,
           expected_game_id,
           game_id
         }}
      end
    end
  end

  defp read_game_occurrences(
         storage,
         game_id,
         first_occurrence_id,
         occurrence_count
       ) do
    0..(occurrence_count - 1)
    |> Enum.reduce_while(
      {:ok, []},
      fn ply, {:ok, reversed} ->
        occurrence_id =
          first_occurrence_id +
            ply

        case OccurrenceStore.get(
               storage.occurrence_store,
               occurrence_id
             ) do
          {:ok,
           %Occurrence{
             game_id: ^game_id,
             ply: ^ply
           } = occurrence} ->
            {:cont,
             {:ok,
              [
                occurrence
                | reversed
              ]}}

          {:ok, %Occurrence{}} ->
            {:halt,
             {:error,
              {
                :invalid_game_occurrence,
                occurrence_id
              }}}

          :not_found ->
            {:halt,
             {:error,
              {
                :missing_occurrence,
                occurrence_id
              }}}

          {:error, _reason} = error ->
            {:halt, error}
        end
      end
    )
    |> case do
      {:ok, reversed} ->
        {:ok, Enum.reverse(reversed)}

      {:error, _reason} = error ->
        error
    end
  end

  defp recover_pending_append(%__MODULE__{} = storage) do
    case OccurrenceAppendMarker.read(storage.directory) do
      :none ->
        :ok

      {:ok,
       %{
         game_id: game_id,
         first_occurrence_id: first_occurrence_id,
         position_ids: position_ids
       }} ->
        recover_pending_append(
          storage,
          game_id,
          first_occurrence_id,
          position_ids
        )

      {:error, _reason} = error ->
        error
    end
  end

  defp recover_pending_append(
         storage,
         game_id,
         first_occurrence_id,
         position_ids
       ) do
    occurrence_count =
      length(position_ids)

    with :ok <-
           OccurrenceStore.recover_pending_append(
             storage.occurrence_store,
             game_id,
             first_occurrence_id,
             position_ids
           ),
         :ok <-
           GameOccurrenceIndex.recover_pending_append(
             storage.game_index,
             game_id,
             first_occurrence_id,
             occurrence_count
           ),
         :ok <-
           PositionOccurrenceIndex.recover_pending_appends(
             storage.position_index,
             position_postings(
               position_ids,
               first_occurrence_id
             )
           ),
         :ok <-
           OccurrenceAppendMarker.clear(storage.directory) do
      :ok
    end
  end

  defp position_postings(
         position_ids,
         first_occurrence_id
       ) do
    position_ids
    |> Enum.with_index(first_occurrence_id)
    |> Enum.map(fn
      {
        position_id,
        occurrence_id
      } ->
        {
          position_id,
          occurrence_id
        }
    end)
  end

  defp ensure_no_pending_append(%__MODULE__{} = storage) do
    case OccurrenceAppendMarker.read(storage.directory) do
      :none ->
        :ok

      {:ok,
       %{
         game_id: game_id
       }} ->
        {:error,
         {
           :incomplete_append,
           game_id
         }}

      {:error, _reason} = error ->
        error
    end
  end

  defp validate_open_storage(storage) do
    with {:ok, occurrence_count} <-
           OccurrenceStore.cardinality(storage.occurrence_store),
         {:ok, game_count} <-
           GameOccurrenceIndex.cardinality(storage.game_index) do
      validate_storage_counts(
        storage,
        game_count,
        occurrence_count
      )
    end
  end

  defp validate_storage_counts(
         _storage,
         0,
         0
       ) do
    :ok
  end

  defp validate_storage_counts(
         _storage,
         0,
         occurrence_count
       ) do
    {:error,
     {
       :orphan_occurrences,
       occurrence_count
     }}
  end

  defp validate_storage_counts(
         storage,
         game_count,
         occurrence_count
       ) do
    case GameOccurrenceIndex.get(
           storage.game_index,
           game_count
         ) do
      {:ok,
       {
         first_occurrence_id,
         count
       }} ->
        expected_occurrence_count =
          first_occurrence_id +
            count -
            1

        if occurrence_count ==
             expected_occurrence_count do
          :ok
        else
          {:error,
           {
             :occurrence_count_mismatch,
             expected_occurrence_count,
             occurrence_count
           }}
        end

      :not_found ->
        {:error,
         {
           :missing_game_occurrence_span,
           game_count
         }}

      {:error, _reason} = error ->
        error
    end
  end

  defp create_components(
         directory,
         position_bucket_count
       ) do
    with {:ok, occurrence_store} <-
           OccurrenceStore.create(occurrence_records_directory(directory)),
         {:ok, game_index} <-
           GameOccurrenceIndex.create(game_index_directory(directory)),
         :ok <-
           create_directory(position_index_directory(directory)) do
      {:ok,
       build_storage(
         directory,
         occurrence_store,
         game_index,
         position_bucket_count
       )}
    end
  end

  defp build_storage(
         directory,
         occurrence_store,
         game_index,
         position_bucket_count
       ) do
    %__MODULE__{
      directory: directory,
      occurrence_store: occurrence_store,
      game_index: game_index,
      position_index:
        PositionOccurrenceIndex.new(
          position_index_directory(directory),
          bucket_count: position_bucket_count
        )
    }
  end

  defp position_bucket_count(opts) do
    bucket_count =
      Keyword.fetch!(
        opts,
        :position_bucket_count
      )

    unless is_integer(bucket_count) and
             bucket_count > 0 do
      raise ArgumentError,
            "position_bucket_count must be positive"
    end

    bucket_count
  end

  defp occurrence_records_directory(directory) do
    Path.join(
      directory,
      "records"
    )
  end

  defp game_index_directory(directory) do
    Path.join(
      directory,
      "game-index"
    )
  end

  defp position_index_directory(directory) do
    Path.join(
      directory,
      "position-index"
    )
  end

  defp create_root_directory(directory) do
    with :ok <-
           File.mkdir(directory),
         :ok <-
           sync_directory(Path.dirname(directory)) do
      :ok
    end
  end

  defp create_directory(directory) do
    with :ok <-
           File.mkdir(directory),
         :ok <-
           sync_directory(Path.dirname(directory)) do
      :ok
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
