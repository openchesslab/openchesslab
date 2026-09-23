defmodule PositionDB.Storage.Disk.RecordStore do
  @moduledoc """
  Reads and appends fixed-size records in disk segments.
  """

  alias PositionDB.Storage.Disk.Layout

  @type t :: %__MODULE__{
          directory: Path.t(),
          record_size: pos_integer(),
          records_per_segment: pos_integer()
        }

  defstruct [
    :directory,
    :record_size,
    :records_per_segment
  ]

  @spec new(Path.t(), keyword()) :: t()
  def new(directory, opts)
      when is_binary(directory) do
    record_size =
      Keyword.fetch!(opts, :record_size)

    records_per_segment =
      Keyword.fetch!(
        opts,
        :records_per_segment
      )

    if record_size <= 0 or
         records_per_segment <= 0 do
      raise ArgumentError,
            "record_size and records_per_segment must be positive"
    end

    %__MODULE__{
      directory: directory,
      record_size: record_size,
      records_per_segment: records_per_segment
    }
  end

  @spec get(t(), pos_integer()) ::
          {:ok, binary()}
          | :not_found
          | {:error, :partial_record}
          | {:error, term()}
  def get(
        %__MODULE__{} = store,
        position_id
      )
      when is_integer(position_id) and
             position_id > 0 do
    {segment, offset} =
      Layout.location(
        position_id,
        store.record_size,
        store.records_per_segment
      )

    path =
      Layout.segment_path(
        store.directory,
        segment
      )

    case :file.open(
           path,
           [:read, :binary, :raw]
         ) do
      {:ok, file} ->
        try do
          read_record(
            file,
            offset,
            store.record_size
          )
        after
          :file.close(file)
        end

      {:error, :enoent} ->
        :not_found

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec append(t(), pos_integer(), binary()) ::
          :ok
          | {:error, :invalid_record_size}
          | {:error, {:unexpected_segment_size, non_neg_integer(), non_neg_integer()}}
          | {:error, :previous_segment_incomplete}
          | {:error, term()}
  def append(
        %__MODULE__{} = store,
        position_id,
        record
      )
      when is_integer(position_id) and
             position_id > 0 and
             is_binary(record) do
    if byte_size(record) == store.record_size do
      {segment, offset} =
        Layout.location(
          position_id,
          store.record_size,
          store.records_per_segment
        )

      path =
        Layout.segment_path(
          store.directory,
          segment
        )

      with :ok <-
             validate_previous_segment(
               store,
               segment,
               offset
             ),
           :ok <-
             validate_segment_size(
               path,
               offset
             ) do
        append_record(path, record)
      end
    else
      {:error, :invalid_record_size}
    end
  end

  defp validate_previous_segment(
         _store,
         0,
         _offset
       ) do
    :ok
  end

  defp validate_previous_segment(
         _store,
         _segment,
         offset
       )
       when offset > 0 do
    :ok
  end

  defp validate_previous_segment(
         store,
         segment,
         0
       ) do
    previous_path =
      Layout.segment_path(
        store.directory,
        segment - 1
      )

    expected_size =
      store.record_size *
        store.records_per_segment

    case File.stat(previous_path) do
      {:ok, %{size: ^expected_size}} ->
        :ok

      {:ok, _stat} ->
        {:error, :previous_segment_incomplete}

      {:error, :enoent} ->
        {:error, :previous_segment_incomplete}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_segment_size(path, expected_size) do
    case File.stat(path) do
      {:ok, %{size: ^expected_size}} ->
        :ok

      {:ok, %{size: actual_size}} ->
        {:error, {:unexpected_segment_size, expected_size, actual_size}}

      {:error, :enoent}
      when expected_size == 0 ->
        :ok

      {:error, :enoent} ->
        {:error, {:unexpected_segment_size, expected_size, 0}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp append_record(path, record) do
    case :file.open(
           path,
           [:append, :binary, :raw]
         ) do
      {:ok, file} ->
        try do
          :file.write(file, record)
        after
          :file.close(file)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_record(
         file,
         offset,
         record_size
       ) do
    case :file.pread(
           file,
           offset,
           record_size
         ) do
      {:ok, record}
      when byte_size(record) == record_size ->
        {:ok, record}

      {:ok, _partial_record} ->
        {:error, :partial_record}

      :eof ->
        :not_found

      {:error, reason} ->
        {:error, reason}
    end
  end
end
