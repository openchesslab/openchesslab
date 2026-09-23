defmodule PositionDB.Storage.Disk.RecordStore do
  @moduledoc """
  Reads fixed-size records from disk segments.
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
