defmodule PositionDB.Storage.Disk.Manifest do
  @moduledoc """
  Durable description of a disk storage layout.

  A manifest identifies the physical formats and layout parameters
  required to interpret an existing PositionDB disk store.

  The manifest format itself is versioned independently from the
  position record and exact-index hash formats.
  """

  @magic <<"OCLPDB01">>
  @magic_size byte_size(@magic)
  @version 1

  @max_u32 4_294_967_295
  @max_u64 18_446_744_073_709_551_615

  @type t :: %__MODULE__{
          record_format_id: binary(),
          record_size: pos_integer(),
          records_per_segment: pos_integer(),
          exact_hash_format_id: binary(),
          exact_hash_size: pos_integer(),
          exact_bucket_count: pos_integer()
        }

  defstruct [
    :record_format_id,
    :record_size,
    :records_per_segment,
    :exact_hash_format_id,
    :exact_hash_size,
    :exact_bucket_count
  ]

  @spec encode(t()) ::
          {:ok, binary()}
          | {:error, :invalid_manifest}
  def encode(%__MODULE__{} = manifest) do
    with :ok <- validate(manifest) do
      record_format_id_size =
        byte_size(manifest.record_format_id)

      exact_hash_format_id_size =
        byte_size(manifest.exact_hash_format_id)

      {:ok,
       <<
         @magic::binary,
         @version::unsigned-big-16,
         manifest.record_size::unsigned-big-32,
         manifest.records_per_segment::unsigned-big-64,
         manifest.exact_hash_size::unsigned-big-32,
         manifest.exact_bucket_count::unsigned-big-64,
         record_format_id_size::unsigned-big-32,
         exact_hash_format_id_size::unsigned-big-32,
         manifest.record_format_id::binary,
         manifest.exact_hash_format_id::binary
       >>}
    end
  end

  @spec decode(binary()) ::
          {:ok, t()}
          | {:error, :invalid_manifest}
          | {:error, :invalid_manifest_magic}
          | {:error, :invalid_manifest_size}
          | {:error, {:unsupported_manifest_version, non_neg_integer()}}
  def decode(encoded)
      when is_binary(encoded) do
    case encoded do
      <<
        magic::binary-size(@magic_size),
        version::unsigned-big-16,
        record_size::unsigned-big-32,
        records_per_segment::unsigned-big-64,
        exact_hash_size::unsigned-big-32,
        exact_bucket_count::unsigned-big-64,
        record_format_id_size::unsigned-big-32,
        exact_hash_format_id_size::unsigned-big-32,
        formats::binary
      >> ->
        decode_manifest(
          magic,
          version,
          record_size,
          records_per_segment,
          exact_hash_size,
          exact_bucket_count,
          record_format_id_size,
          exact_hash_format_id_size,
          formats
        )

      _other ->
        {:error, :invalid_manifest}
    end
  end

  def decode(_encoded) do
    {:error, :invalid_manifest}
  end

  defp decode_manifest(
         magic,
         _version,
         _record_size,
         _records_per_segment,
         _exact_hash_size,
         _exact_bucket_count,
         _record_format_id_size,
         _exact_hash_format_id_size,
         _formats
       )
       when magic != @magic do
    {:error, :invalid_manifest_magic}
  end

  defp decode_manifest(
         @magic,
         version,
         _record_size,
         _records_per_segment,
         _exact_hash_size,
         _exact_bucket_count,
         _record_format_id_size,
         _exact_hash_format_id_size,
         _formats
       )
       when version != @version do
    {:error, {:unsupported_manifest_version, version}}
  end

  defp decode_manifest(
         @magic,
         @version,
         record_size,
         records_per_segment,
         exact_hash_size,
         exact_bucket_count,
         record_format_id_size,
         exact_hash_format_id_size,
         formats
       ) do
    expected_size =
      record_format_id_size +
        exact_hash_format_id_size

    if byte_size(formats) == expected_size do
      <<
        record_format_id::binary-size(^record_format_id_size),
        exact_hash_format_id::binary-size(^exact_hash_format_id_size)
      >> = formats

      manifest = %__MODULE__{
        record_format_id: record_format_id,
        record_size: record_size,
        records_per_segment: records_per_segment,
        exact_hash_format_id: exact_hash_format_id,
        exact_hash_size: exact_hash_size,
        exact_bucket_count: exact_bucket_count
      }

      case validate(manifest) do
        :ok ->
          {:ok, manifest}

        {:error, :invalid_manifest} ->
          {:error, :invalid_manifest}
      end
    else
      {:error, :invalid_manifest_size}
    end
  end

  defp validate(%__MODULE__{
         record_format_id: record_format_id,
         record_size: record_size,
         records_per_segment: records_per_segment,
         exact_hash_format_id: exact_hash_format_id,
         exact_hash_size: exact_hash_size,
         exact_bucket_count: exact_bucket_count
       })
       when is_binary(record_format_id) and
              byte_size(record_format_id) > 0 and
              byte_size(record_format_id) <= @max_u32 and
              is_integer(record_size) and
              record_size > 0 and
              record_size <= @max_u32 and
              is_integer(records_per_segment) and
              records_per_segment > 0 and
              records_per_segment <= @max_u64 and
              is_binary(exact_hash_format_id) and
              byte_size(exact_hash_format_id) > 0 and
              byte_size(exact_hash_format_id) <= @max_u32 and
              is_integer(exact_hash_size) and
              exact_hash_size > 0 and
              exact_hash_size <= @max_u32 and
              is_integer(exact_bucket_count) and
              exact_bucket_count > 0 and
              exact_bucket_count <= @max_u64 do
    :ok
  end

  defp validate(%__MODULE__{}) do
    {:error, :invalid_manifest}
  end
end
