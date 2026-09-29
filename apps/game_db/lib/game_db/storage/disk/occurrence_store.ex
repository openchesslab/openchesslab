defmodule GameDB.Storage.Disk.OccurrenceStore do
  @moduledoc """
  Append-only storage for fixed-size position occurrences.

  Occurrence IDs are implicit and sequential, starting at one.
  They are derived from the record's physical position and are
  therefore not stored in each record.

  Physical record format:

    * 8 byte unsigned game ID
    * 4 byte unsigned ply
    * 8 byte unsigned position ID

  Each occurrence therefore occupies exactly 20 bytes.
  """

  alias GameDB.Occurrence

  @filename "occurrences.dat"

  @record_size 20
  @max_game_id 0xFFFF_FFFF_FFFF_FFFF
  @max_ply 0xFFFF_FFFF
  @max_position_id 0xFFFF_FFFF_FFFF_FFFF
  @max_occurrence_id 0xFFFF_FFFF_FFFF_FFFF

  @type t :: %__MODULE__{
          directory: Path.t(),
          path: Path.t()
        }

  @enforce_keys [
    :directory,
    :path
  ]

  defstruct [
    :directory,
    :path
  ]

  @spec create(Path.t()) ::
          {:ok, t()}
          | {:error, :storage_exists}
          | {:error, term()}
  def create(directory)
      when is_binary(directory) do
    store =
      new(directory)

    case create_directory(directory) do
      :ok ->
        case create_empty_file(store.path) do
          :ok ->
            {:ok, store}

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

  @spec open(Path.t()) ::
          {:ok, t()}
          | {:error, term()}
  def open(directory)
      when is_binary(directory) do
    store =
      new(directory)

    with :ok <-
           validate_directory(directory),
         :ok <-
           validate_regular_file(store.path) do
      {:ok, store}
    end
  end

  @spec append(
          t(),
          pos_integer(),
          [pos_integer()]
        ) ::
          {:ok, pos_integer(), pos_integer()}
          | {:error, term()}
  def append(
        %__MODULE__{} = store,
        game_id,
        position_ids
      )
      when is_integer(game_id) and
             game_id > 0 and
             is_list(position_ids) do
    with :ok <-
           validate_game_id(game_id),
         :ok <-
           validate_position_ids(position_ids),
         {:ok, count} <-
           cardinality(store) do
      occurrence_count =
        length(position_ids)

      first_occurrence_id =
        count + 1

      records =
        encode_records(
          game_id,
          position_ids
        )

      case append_and_sync(
             store.path,
             records
           ) do
        :ok ->
          {:ok, first_occurrence_id, occurrence_count}

        {:error, reason} ->
          {:error, reason}
      end
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

  @doc """
  Recovers one interrupted occurrence batch append.

  Existing bytes belonging to the pending batch must exactly match a
  prefix of the expected batch. A partial matching batch is truncated
  back to its starting offset and rewritten completely.

  A complete matching batch is preserved. Unexpected bytes are never
  modified.
  """
  @spec recover_pending_append(
          t(),
          pos_integer(),
          pos_integer(),
          [pos_integer()]
        ) ::
          :ok
          | {:error, term()}
  def recover_pending_append(
        %__MODULE__{} = store,
        game_id,
        first_occurrence_id,
        position_ids
      )
      when is_integer(game_id) and
             game_id > 0 and
             is_integer(first_occurrence_id) and
             first_occurrence_id > 0 and
             is_list(position_ids) do
    with :ok <-
           validate_game_id(game_id),
         :ok <-
           validate_first_occurrence_id(first_occurrence_id),
         :ok <-
           validate_position_ids(position_ids),
         :ok <-
           validate_occurrence_range(
             first_occurrence_id,
             length(position_ids)
           ),
         {:ok, size} <-
           file_size(store.path) do
      expected_offset =
        (first_occurrence_id - 1) *
          @record_size

      expected =
        game_id
        |> encode_records(position_ids)
        |> IO.iodata_to_binary()

      recover_batch(
        store.path,
        size,
        expected_offset,
        expected
      )
    end
  end

  def recover_pending_append(
        %__MODULE__{},
        _game_id,
        _first_occurrence_id,
        _position_ids
      ) do
    {:error, :invalid_recovery_batch}
  end

  @spec get(
          t(),
          pos_integer()
        ) ::
          {:ok, Occurrence.t()}
          | :not_found
          | {:error, term()}
  def get(
        %__MODULE__{} = store,
        occurrence_id
      )
      when is_integer(occurrence_id) and
             occurrence_id > 0 do
    case cardinality(store) do
      {:ok, count}
      when occurrence_id > count ->
        :not_found

      {:ok, _count} ->
        offset =
          (occurrence_id - 1) *
            @record_size

        case pread(
               store.path,
               offset,
               @record_size
             ) do
          {:ok, record}
          when byte_size(record) ==
                 @record_size ->
            decode_record(
              occurrence_id,
              record
            )

          {:ok, _partial} ->
            {:error, :partial_record}

          :eof ->
            {:error, :partial_record}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec cardinality(t()) ::
          {:ok, non_neg_integer()}
          | {:error, :partial_record}
          | {:error, term()}
  def cardinality(%__MODULE__{} = store) do
    case File.stat(store.path) do
      {:ok, %{size: size}} ->
        if rem(
             size,
             @record_size
           ) == 0 do
          {:ok,
           div(
             size,
             @record_size
           )}
        else
          {:error, :partial_record}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp new(directory) do
    %__MODULE__{
      directory: directory,
      path:
        Path.join(
          directory,
          @filename
        )
    }
  end

  defp encode_records(
         game_id,
         position_ids
       ) do
    position_ids
    |> Enum.with_index()
    |> Enum.map(fn {position_id, ply} ->
      <<
        game_id::unsigned-big-64,
        ply::unsigned-big-32,
        position_id::unsigned-big-64
      >>
    end)
  end

  defp decode_record(
         occurrence_id,
         <<
           game_id::unsigned-big-64,
           ply::unsigned-big-32,
           position_id::unsigned-big-64
         >>
       )
       when game_id > 0 and
              position_id > 0 do
    {:ok,
     Occurrence.new(
       occurrence_id,
       game_id,
       ply,
       position_id
     )}
  end

  defp decode_record(
         _occurrence_id,
         _record
       ) do
    {:error, :invalid_occurrence_record}
  end

  defp validate_game_id(game_id)
       when game_id <= @max_game_id do
    :ok
  end

  defp validate_game_id(_game_id) do
    {:error, :invalid_game_id}
  end

  defp validate_position_ids([]) do
    {:error, :missing_initial_position}
  end

  defp validate_position_ids(position_ids) do
    occurrence_count =
      length(position_ids)

    cond do
      occurrence_count - 1 >
          @max_ply ->
        {:error, :too_many_occurrences}

      Enum.all?(
        position_ids,
        fn position_id ->
          is_integer(position_id) and
            position_id > 0 and
              position_id <=
                @max_position_id
        end
      ) ->
        :ok

      true ->
        {:error, :invalid_position_ids}
    end
  end

  defp append_and_sync(
         path,
         records
       ) do
    case :file.open(
           path,
           [
             :append,
             :binary,
             :raw
           ]
         ) do
      {:ok, file} ->
        try do
          with :ok <-
                 :file.write(
                   file,
                   records
                 ),
               :ok <-
                 :file.sync(file) do
            :ok
          end
        after
          :file.close(file)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp pread(
         path,
         offset,
         size
       ) do
    case :file.open(
           path,
           [
             :read,
             :binary,
             :raw
           ]
         ) do
      {:ok, file} ->
        try do
          :file.pread(
            file,
            offset,
            size
          )
        after
          :file.close(file)
        end

      {:error, reason} ->
        {:error, reason}
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

  defp create_empty_file(path) do
    case :file.open(
           path,
           [
             :write,
             :binary,
             :raw,
             :exclusive
           ]
         ) do
      {:ok, file} ->
        result =
          try do
            :file.sync(file)
          after
            :file.close(file)
          end

        with :ok <- result,
             :ok <-
               sync_directory(Path.dirname(path)) do
          :ok
        end

      {:error, reason} ->
        {:error, reason}
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

  defp validate_regular_file(path) do
    case File.stat(path) do
      {:ok, %{type: :regular}} ->
        :ok

      {:ok, _stat} ->
        {:error, :not_a_regular_file}

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

  defp recover_batch(
         path,
         actual_size,
         expected_offset,
         expected
       ) do
    expected_end =
      expected_offset +
        byte_size(expected)

    cond do
      actual_size < expected_offset ->
        {:error,
         {
           :unexpected_occurrence_store_size,
           expected_offset,
           actual_size
         }}

      actual_size == expected_offset ->
        append_and_sync(
          path,
          expected
        )

      actual_size < expected_end ->
        recover_partial_batch(
          path,
          expected_offset,
          actual_size - expected_offset,
          expected
        )

      actual_size == expected_end ->
        recover_complete_batch(
          path,
          expected_offset,
          expected
        )

      actual_size > expected_end ->
        {:error,
         {
           :unexpected_occurrence_store_size,
           expected_end,
           actual_size
         }}
    end
  end

  defp recover_partial_batch(
         path,
         offset,
         partial_size,
         expected
       ) do
    with {:ok, partial} <-
           read_exact(
             path,
             offset,
             partial_size
           ),
         :ok <-
           validate_batch_prefix(
             partial,
             expected
           ),
         :ok <-
           truncate_file(
             path,
             offset
           ),
         :ok <-
           append_and_sync(
             path,
             expected
           ) do
      :ok
    end
  end

  defp recover_complete_batch(
         path,
         offset,
         expected
       ) do
    with {:ok, actual} <-
           read_exact(
             path,
             offset,
             byte_size(expected)
           ) do
      if actual == expected do
        sync_file(path)
      else
        {:error, :unexpected_occurrence_batch}
      end
    end
  end

  defp validate_batch_prefix(
         partial,
         expected
       ) do
    if partial ==
         binary_part(
           expected,
           0,
           byte_size(partial)
         ) do
      :ok
    else
      {:error, :unexpected_partial_occurrence_batch}
    end
  end

  defp validate_first_occurrence_id(occurrence_id)
       when occurrence_id <=
              @max_occurrence_id do
    :ok
  end

  defp validate_first_occurrence_id(_occurrence_id) do
    {:error, :invalid_occurrence_id}
  end

  defp validate_occurrence_range(
         first_occurrence_id,
         count
       ) do
    last_occurrence_id =
      first_occurrence_id +
        count -
        1

    if last_occurrence_id <=
         @max_occurrence_id do
      :ok
    else
      {:error, :occurrence_id_overflow}
    end
  end

  defp file_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} ->
        {:ok, size}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_exact(
         path,
         offset,
         size
       ) do
    case pread(
           path,
           offset,
           size
         ) do
      {:ok, binary}
      when byte_size(binary) ==
             size ->
        {:ok, binary}

      {:ok, _partial} ->
        {:error, :partial_record}

      :eof ->
        {:error, :partial_record}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp truncate_file(
         path,
         size
       ) do
    case :file.open(
           path,
           [
             :read,
             :write,
             :binary,
             :raw
           ]
         ) do
      {:ok, file} ->
        try do
          with {:ok, ^size} <-
                 :file.position(
                   file,
                   size
                 ),
               :ok <-
                 :file.truncate(file),
               :ok <-
                 :file.sync(file) do
            :ok
          end
        after
          :file.close(file)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp sync_file(path) do
    case :file.open(
           path,
           [
             :read,
             :write,
             :binary,
             :raw
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
  end
end
