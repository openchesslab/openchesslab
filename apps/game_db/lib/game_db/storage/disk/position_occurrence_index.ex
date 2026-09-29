defmodule GameDB.Storage.Disk.PositionOccurrenceIndex do
  @moduledoc """
  Disk-backed posting index from position IDs to occurrence IDs.

  Entries are distributed across buckets using the position ID.
  Every fixed-size entry contains:

    * 8 byte unsigned position ID
    * 8 byte unsigned occurrence ID

  The complete position ID remains stored in every entry, so bucket
  collisions cannot affect lookup semantics.

  Scans are incremental and do not materialize all matching occurrence
  IDs in memory.
  """

  @entry_size 16
  @max_id 0xFFFF_FFFF_FFFF_FFFF

  @type t :: %__MODULE__{
          directory: Path.t(),
          bucket_count: pos_integer()
        }

  @type posting :: {
          pos_integer(),
          pos_integer()
        }

  @type scan_state :: %{
          path: Path.t(),
          position_id: pos_integer(),
          offset: non_neg_integer()
        }

  defstruct [
    :directory,
    :bucket_count
  ]

  @spec new(Path.t(), keyword()) :: t()
  def new(directory, opts) when is_binary(directory) do
    bucket_count =
      Keyword.fetch!(
        opts,
        :bucket_count
      )

    if bucket_count <= 0 do
      raise ArgumentError,
            "bucket_count must be positive"
    end

    %__MODULE__{
      directory: directory,
      bucket_count: bucket_count
    }
  end

  @spec add_all(
          t(),
          [posting()]
        ) ::
          {:ok, t()}
          | {:error, term()}
  def add_all(%__MODULE__{} = index, postings) when is_list(postings) do
    with {:ok, postings} <-
           validate_postings(postings) do
      postings
      |> Enum.group_by(fn
        {position_id, _occurrence_id} ->
          bucket(
            index,
            position_id
          )
      end)
      |> Enum.sort_by(fn
        {bucket, _postings} ->
          bucket
      end)
      |> Enum.reduce_while(
        {:ok, index},
        fn {bucket, bucket_postings}, {:ok, index} ->
          case append_bucket_postings(
                 index,
                 bucket,
                 bucket_postings
               ) do
            :ok ->
              {:cont, {:ok, index}}

            {:error, reason} ->
              {:halt, {:error, reason}}
          end
        end
      )
    end
  end

  @spec scan(
          t(),
          pos_integer()
        ) ::
          scan_state()
  def scan(%__MODULE__{} = index, position_id)
      when is_integer(position_id) and position_id > 0 and position_id <= @max_id do
    %{
      path:
        bucket_path(
          index,
          position_id
        ),
      position_id: position_id,
      offset: 0
    }
  end

  @spec scan_next(scan_state()) ::
          {:ok, pos_integer(), scan_state()}
          | :done
          | {:error, term()}
  def scan_next(%{path: path, position_id: position_id, offset: offset} = state) do
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
          scan_file(
            file,
            position_id,
            offset,
            state
          )
        after
          :file.close(file)
        end

      {:error, :enoent} ->
        :done

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Recovers all position postings belonging to one interrupted logical append.

  Complete expected postings are preserved. A partial bucket tail is only
  truncated when it matches a prefix of one of the expected postings.

  Any expected posting that is still missing is appended durably.
  """
  @spec recover_pending_appends(
          t(),
          [posting()]
        ) ::
          :ok
          | {:error, term()}
  def recover_pending_appends(%__MODULE__{} = index, postings) when is_list(postings) do
    with {:ok, postings} <-
           validate_postings(postings) do
      postings
      |> Enum.group_by(fn
        {position_id, _occurrence_id} ->
          bucket(
            index,
            position_id
          )
      end)
      |> Enum.sort_by(fn
        {bucket, _postings} ->
          bucket
      end)
      |> Enum.reduce_while(
        :ok,
        fn {bucket, bucket_postings}, :ok ->
          case recover_bucket(
                 index,
                 bucket,
                 bucket_postings
               ) do
            :ok ->
              {:cont, :ok}

            {:error, reason} ->
              {:halt, {:error, reason}}
          end
        end
      )
    end
  end

  defp append_bucket_postings(index, bucket, postings) do
    path =
      bucket_file_path(
        index,
        bucket
      )

    with {:ok, bucket_state} <-
           bucket_state(path) do
      entries =
        Enum.map(
          postings,
          &encode/1
        )

      append_entries(
        index,
        path,
        bucket_state,
        entries
      )
    end
  end

  defp scan_file(file, position_id, offset, state) do
    case :file.pread(
           file,
           offset,
           @entry_size
         ) do
      {:ok, entry}
      when byte_size(entry) ==
             @entry_size ->
        with {:ok, stored_position_id, occurrence_id} <-
               decode(entry) do
          next_offset =
            offset +
              @entry_size

          if stored_position_id ==
               position_id do
            {:ok, occurrence_id,
             %{
               state
               | offset: next_offset
             }}
          else
            scan_file(
              file,
              position_id,
              next_offset,
              state
            )
          end
        end

      {:ok, _partial} ->
        {:error, :partial_entry}

      :eof ->
        :done

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp recover_bucket(index, bucket, postings) do
    path =
      bucket_file_path(
        index,
        bucket
      )

    expected =
      postings
      |> Enum.uniq()
      |> Enum.map(fn posting ->
        {
          posting,
          encode(posting)
        }
      end)

    case File.stat(path) do
      {:ok,
       %{
         type: :regular,
         size: size
       }} ->
        recover_existing_bucket(
          index,
          path,
          size,
          expected
        )

      {:ok, _stat} ->
        {:error, :not_a_regular_file}

      {:error, :enoent} ->
        persist_missing(
          index,
          path,
          :new,
          expected,
          %{}
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp recover_existing_bucket(index, path, size, expected) do
    complete_size =
      div(
        size,
        @entry_size
      ) *
        @entry_size

    partial_size =
      size -
        complete_size

    expected_postings =
      Map.new(
        expected,
        fn {posting, _entry} ->
          {
            posting,
            true
          }
        end
      )

    with {:ok, found} <-
           inspect_complete_entries(
             path,
             complete_size,
             expected_postings
           ),
         :ok <-
           recover_partial_tail(
             path,
             complete_size,
             partial_size,
             expected
           ) do
      persist_missing(
        index,
        path,
        :existing,
        expected,
        found
      )
    end
  end

  defp inspect_complete_entries(path, complete_size, expected) do
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
          inspect_complete_entries(
            file,
            0,
            complete_size,
            expected,
            %{}
          )
        after
          :file.close(file)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp inspect_complete_entries(_file, offset, complete_size, _expected, found)
       when offset == complete_size do
    {:ok, found}
  end

  defp inspect_complete_entries(file, offset, complete_size, expected, found) do
    case :file.pread(
           file,
           offset,
           @entry_size
         ) do
      {:ok, entry}
      when byte_size(entry) ==
             @entry_size ->
        with {:ok, position_id, occurrence_id} <-
               decode(entry) do
          posting =
            {
              position_id,
              occurrence_id
            }

          found =
            if Map.has_key?(
                 expected,
                 posting
               ) do
              Map.put(
                found,
                posting,
                true
              )
            else
              found
            end

          inspect_complete_entries(
            file,
            offset + @entry_size,
            complete_size,
            expected,
            found
          )
        end

      {:ok, _partial} ->
        {:error, :partial_entry}

      :eof ->
        {:error, :partial_entry}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp recover_partial_tail(_path, _offset, 0, _expected) do
    :ok
  end

  defp recover_partial_tail(path, offset, partial_size, expected) do
    with {:ok, partial} <-
           read_exact(
             path,
             offset,
             partial_size
           ),
         :ok <-
           validate_partial(
             partial,
             expected
           ) do
      truncate_file(
        path,
        offset
      )
    end
  end

  defp validate_partial(partial, expected) do
    matches? =
      Enum.any?(
        expected,
        fn {_posting, entry} ->
          partial ==
            binary_part(
              entry,
              0,
              byte_size(partial)
            )
        end
      )

    if matches? do
      :ok
    else
      {:error, :unexpected_partial_entry}
    end
  end

  defp persist_missing(index, path, bucket_state, expected, found) do
    missing =
      Enum.reject(
        expected,
        fn {posting, _entry} ->
          Map.has_key?(
            found,
            posting
          )
        end
      )

    entries =
      Enum.map(
        missing,
        fn {_posting, entry} ->
          entry
        end
      )

    case entries do
      [] ->
        sync_existing_file(
          path,
          bucket_state
        )

      _entries ->
        append_entries(
          index,
          path,
          bucket_state,
          entries
        )
    end
  end

  defp append_entries(index, path, bucket_state, entries) do
    case :file.open(
           path,
           [
             :append,
             :binary,
             :raw
           ]
         ) do
      {:ok, file} ->
        result =
          try do
            with :ok <-
                   :file.write(
                     file,
                     entries
                   ) do
              :file.sync(file)
            end
          after
            :file.close(file)
          end

        with :ok <- result do
          sync_new_bucket(
            index,
            bucket_state
          )
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp bucket_state(path) do
    case File.stat(path) do
      {:ok,
       %{
         type: :regular,
         size: size
       }} ->
        if rem(
             size,
             @entry_size
           ) == 0 do
          {:ok, :existing}
        else
          {:error, :partial_entry}
        end

      {:ok, _stat} ->
        {:error, :not_a_regular_file}

      {:error, :enoent} ->
        {:ok, :new}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp bucket(%__MODULE__{bucket_count: bucket_count}, position_id) do
    rem(
      position_id,
      bucket_count
    )
  end

  defp bucket_path(%__MODULE__{} = index, position_id) do
    index
    |> bucket(position_id)
    |> then(
      &bucket_file_path(
        index,
        &1
      )
    )
  end

  defp bucket_file_path(%__MODULE__{directory: directory}, bucket)
       when is_integer(bucket) and bucket >= 0 do
    filename =
      bucket
      |> Integer.to_string()
      |> String.pad_leading(
        8,
        "0"
      )
      |> then(&"bucket-#{&1}.idx")

    Path.join(
      directory,
      filename
    )
  end

  defp encode({position_id, occurrence_id}) do
    <<
      position_id::unsigned-big-64,
      occurrence_id::unsigned-big-64
    >>
  end

  defp decode(<<position_id::unsigned-big-64, occurrence_id::unsigned-big-64>>)
       when position_id > 0 and occurrence_id > 0 do
    {:ok, position_id, occurrence_id}
  end

  defp decode(_entry) do
    {:error, :invalid_entry}
  end

  defp validate_postings(postings) do
    postings
    |> Enum.reduce_while(
      {:ok, []},
      fn
        {
          position_id,
          occurrence_id
        },
        {:ok, valid}
        when is_integer(position_id) and
               position_id > 0 and
               position_id <= @max_id and
               is_integer(occurrence_id) and
               occurrence_id > 0 and
               occurrence_id <= @max_id ->
          {:cont,
           {:ok,
            [
              {
                position_id,
                occurrence_id
              }
              | valid
            ]}}

        {
          position_id,
          _occurrence_id
        },
        _acc
        when not is_integer(position_id) or
               position_id <= 0 ->
          {:halt, {:error, :invalid_position_id}}

        _posting, _acc ->
          {:halt, {:error, :invalid_occurrence_id}}
      end
    )
    |> case do
      {:ok, valid} ->
        {:ok,
         valid
         |> Enum.reverse()
         |> Enum.uniq()}

      {:error, _reason} = error ->
        error
    end
  end

  defp read_exact(path, offset, size) do
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
          case :file.pread(
                 file,
                 offset,
                 size
               ) do
            {:ok, binary}
            when byte_size(binary) ==
                   size ->
              {:ok, binary}

            {:ok, _partial} ->
              {:error, :partial_entry}

            :eof ->
              {:error, :partial_entry}

            {:error, reason} ->
              {:error, reason}
          end
        after
          :file.close(file)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp truncate_file(path, size) do
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
                 :file.truncate(file) do
            :file.sync(file)
          end
        after
          :file.close(file)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp sync_existing_file(_path, :new) do
    :ok
  end

  defp sync_existing_file(path, :existing) do
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

  defp sync_new_bucket(index, :new) do
    sync_directory(index.directory)
  end

  defp sync_new_bucket(_index, :existing) do
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
