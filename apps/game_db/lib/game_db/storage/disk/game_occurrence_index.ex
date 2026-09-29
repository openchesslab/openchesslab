defmodule GameDB.Storage.Disk.GameOccurrenceIndex do
  @moduledoc """
  Maps game IDs to their contiguous range of occurrence IDs.

  Game IDs are implicit and sequential, starting at one. Each fixed-size
  index entry contains:

    * 8 byte unsigned first occurrence ID
    * 4 byte unsigned occurrence count

  Each game therefore requires exactly 12 bytes of index storage.
  """

  @filename "game-occurrences.idx"

  @entry_size 12
  @max_id 0xFFFF_FFFF_FFFF_FFFF
  @max_count 0xFFFF_FFFF

  @type t :: %__MODULE__{
          directory: Path.t(),
          path: Path.t()
        }

  @type span :: {
          pos_integer(),
          pos_integer()
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
    index =
      new(directory)

    case create_directory(directory) do
      :ok ->
        case create_empty_file(index.path) do
          :ok ->
            {:ok, index}

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
    index =
      new(directory)

    with :ok <-
           validate_directory(directory),
         :ok <-
           validate_regular_file(index.path) do
      {:ok, index}
    end
  end

  @spec append(
          t(),
          pos_integer(),
          pos_integer(),
          pos_integer()
        ) ::
          :ok
          | {:error, term()}
  def append(
        %__MODULE__{} = index,
        game_id,
        first_occurrence_id,
        occurrence_count
      ) do
    with :ok <-
           validate_game_id(game_id),
         :ok <-
           validate_first_occurrence_id(first_occurrence_id),
         :ok <-
           validate_occurrence_count(occurrence_count),
         expected_size <-
           expected_offset(game_id),
         :ok <-
           validate_file_size(
             index.path,
             expected_size
           ) do
      append_and_sync(
        index.path,
        encode(
          first_occurrence_id,
          occurrence_count
        )
      )
    end
  end

  @spec get(
          t(),
          pos_integer()
        ) ::
          {:ok, span()}
          | :not_found
          | {:error, term()}
  def get(
        %__MODULE__{} = index,
        game_id
      )
      when is_integer(game_id) and
             game_id > 0 do
    case cardinality(index) do
      {:ok, count}
      when game_id > count ->
        :not_found

      {:ok, _count} ->
        offset =
          expected_offset(game_id)

        case pread(
               index.path,
               offset,
               @entry_size
             ) do
          {:ok, entry}
          when byte_size(entry) ==
                 @entry_size ->
            decode(entry)

          {:ok, _partial} ->
            {:error, :partial_entry}

          :eof ->
            {:error, :partial_entry}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec cardinality(t()) ::
          {:ok, non_neg_integer()}
          | {:error, :partial_entry}
          | {:error, term()}
  def cardinality(%__MODULE__{} = index) do
    case File.stat(index.path) do
      {:ok, %{size: size}} ->
        if rem(
             size,
             @entry_size
           ) == 0 do
          {:ok,
           div(
             size,
             @entry_size
           )}
        else
          {:error, :partial_entry}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Recovers one interrupted game-occurrence index append.

  A missing entry is appended.

  A matching partial entry is truncated and rewritten completely.

  A complete matching entry is made durable again.

  Existing unrelated data is never modified.
  """
  @spec recover_pending_append(
          t(),
          pos_integer(),
          pos_integer(),
          pos_integer()
        ) ::
          :ok
          | {:error, term()}
  def recover_pending_append(
        %__MODULE__{} = index,
        game_id,
        first_occurrence_id,
        occurrence_count
      ) do
    with :ok <-
           validate_game_id(game_id),
         :ok <-
           validate_first_occurrence_id(first_occurrence_id),
         :ok <-
           validate_occurrence_count(occurrence_count) do
      entry =
        encode(
          first_occurrence_id,
          occurrence_count
        )

      recover_entry(
        index.path,
        expected_offset(game_id),
        entry
      )
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

  defp expected_offset(game_id) do
    (game_id - 1) *
      @entry_size
  end

  defp encode(
         first_occurrence_id,
         occurrence_count
       ) do
    <<
      first_occurrence_id::unsigned-big-64,
      occurrence_count::unsigned-big-32
    >>
  end

  defp decode(<<
         first_occurrence_id::unsigned-big-64,
         occurrence_count::unsigned-big-32
       >>)
       when first_occurrence_id > 0 and
              occurrence_count > 0 do
    {:ok,
     {
       first_occurrence_id,
       occurrence_count
     }}
  end

  defp decode(_entry) do
    {:error, :invalid_entry}
  end

  defp recover_entry(
         path,
         expected_offset,
         entry
       ) do
    case File.stat(path) do
      {:ok, %{size: size}}
      when size == expected_offset ->
        append_and_sync(
          path,
          entry
        )

      {:ok, %{size: size}}
      when size > expected_offset and
             size < expected_offset + @entry_size ->
        recover_partial_entry(
          path,
          expected_offset,
          size - expected_offset,
          entry
        )

      {:ok, %{size: size}}
      when size == expected_offset + @entry_size ->
        recover_complete_entry(
          path,
          expected_offset,
          entry
        )

      {:ok, %{size: size}} ->
        {:error,
         {
           :unexpected_index_size,
           expected_offset,
           size
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp recover_partial_entry(
         path,
         offset,
         partial_size,
         entry
       ) do
    with {:ok, partial} <-
           pread(
             path,
             offset,
             partial_size
           ),
         :ok <-
           validate_partial_entry(
             partial,
             entry
           ),
         :ok <-
           truncate_file(
             path,
             offset
           ),
         :ok <-
           append_and_sync(
             path,
             entry
           ) do
      :ok
    end
  end

  defp recover_complete_entry(
         path,
         offset,
         entry
       ) do
    case pread(
           path,
           offset,
           @entry_size
         ) do
      {:ok, ^entry} ->
        sync_file(path)

      {:ok, _other} ->
        {:error, :unexpected_entry}

      :eof ->
        {:error, :partial_entry}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_partial_entry(
         partial,
         entry
       ) do
    expected =
      binary_part(
        entry,
        0,
        byte_size(partial)
      )

    if partial == expected do
      :ok
    else
      {:error, :unexpected_partial_entry}
    end
  end

  defp validate_file_size(
         path,
         expected_size
       ) do
    case File.stat(path) do
      {:ok, %{size: ^expected_size}} ->
        :ok

      {:ok, %{size: actual_size}} ->
        {:error,
         {
           :unexpected_index_size,
           expected_size,
           actual_size
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_game_id(game_id)
       when is_integer(game_id) and
              game_id > 0 and
              game_id <= @max_id do
    :ok
  end

  defp validate_game_id(_game_id) do
    {:error, :invalid_game_id}
  end

  defp validate_first_occurrence_id(occurrence_id)
       when is_integer(occurrence_id) and
              occurrence_id > 0 and
              occurrence_id <= @max_id do
    :ok
  end

  defp validate_first_occurrence_id(_occurrence_id) do
    {:error, :invalid_occurrence_id}
  end

  defp validate_occurrence_count(count)
       when is_integer(count) and
              count > 0 and
              count <= @max_count do
    :ok
  end

  defp validate_occurrence_count(_count) do
    {:error, :invalid_occurrence_count}
  end

  defp append_and_sync(
         path,
         data
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
                   data
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
end
