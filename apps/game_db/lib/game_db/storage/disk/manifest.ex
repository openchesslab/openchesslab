defmodule GameDB.Storage.Disk.Manifest do
  @moduledoc """
  Durable description of a GameDB disk storage layout.

  The manifest records the physical format and bucket layout required
  to reopen an existing disk store correctly.

  The manifest format is versioned independently from the canonical
  game record format.
  """

  @magic <<"OCLGDB", 0, 0>>
  @magic_size byte_size(@magic)
  @version 1

  @max_u32 0xFFFF_FFFF
  @max_u64 0xFFFF_FFFF_FFFF_FFFF

  @type t :: %__MODULE__{
          record_format_id: binary(),
          canonical_bucket_count: pos_integer(),
          position_bucket_count: pos_integer()
        }

  defstruct [
    :record_format_id,
    :canonical_bucket_count,
    :position_bucket_count
  ]

  @spec encode(t()) ::
          {:ok, binary()}
          | {:error, :invalid_manifest}
  def encode(%__MODULE__{} = manifest) do
    with :ok <- validate(manifest) do
      record_format_id_size =
        byte_size(manifest.record_format_id)

      {:ok,
       <<
         @magic::binary,
         @version::unsigned-big-16,
         manifest.canonical_bucket_count::unsigned-big-64,
         manifest.position_bucket_count::unsigned-big-64,
         record_format_id_size::unsigned-big-32,
         manifest.record_format_id::binary
       >>}
    end
  end

  @spec decode(binary()) ::
          {:ok, t()}
          | {:error, :invalid_manifest}
          | {:error, :invalid_manifest_magic}
          | {:error, :invalid_manifest_size}
          | {:error, {:unsupported_manifest_version, non_neg_integer()}}
  def decode(encoded) when is_binary(encoded) do
    case encoded do
      <<
        magic::binary-size(@magic_size),
        version::unsigned-big-16,
        canonical_bucket_count::unsigned-big-64,
        position_bucket_count::unsigned-big-64,
        record_format_id_size::unsigned-big-32,
        record_format_id::binary
      >> ->
        decode_manifest(
          magic,
          version,
          canonical_bucket_count,
          position_bucket_count,
          record_format_id_size,
          record_format_id
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
         _canonical_bucket_count,
         _position_bucket_count,
         _record_format_id_size,
         _record_format_id
       )
       when magic != @magic do
    {:error, :invalid_manifest_magic}
  end

  defp decode_manifest(
         @magic,
         version,
         _canonical_bucket_count,
         _position_bucket_count,
         _record_format_id_size,
         _record_format_id
       )
       when version != @version do
    {:error, {:unsupported_manifest_version, version}}
  end

  defp decode_manifest(
         @magic,
         @version,
         canonical_bucket_count,
         position_bucket_count,
         record_format_id_size,
         record_format_id
       ) do
    if byte_size(record_format_id) == record_format_id_size do
      manifest = %__MODULE__{
        record_format_id: record_format_id,
        canonical_bucket_count: canonical_bucket_count,
        position_bucket_count: position_bucket_count
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
         canonical_bucket_count: canonical_bucket_count,
         position_bucket_count: position_bucket_count
       })
       when is_binary(record_format_id) and byte_size(record_format_id) > 0 and
              byte_size(record_format_id) <= @max_u32 and is_integer(canonical_bucket_count) and
              canonical_bucket_count > 0 and canonical_bucket_count <= @max_u64 and
              is_integer(position_bucket_count) and position_bucket_count > 0 and
              position_bucket_count <= @max_u64 do
    :ok
  end

  defp validate(%__MODULE__{}) do
    {:error, :invalid_manifest}
  end
end
