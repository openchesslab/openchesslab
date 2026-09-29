defmodule GameDB.Storage.Disk.Manifest do
  @moduledoc """
  Durable description of a GameDB disk storage layout.

  The manifest records the physical formats and bucket layout required
  to reopen an existing disk store correctly.

  The manifest format itself is versioned independently from the
  canonical game record and fingerprint formats.
  """

  @magic <<"OCLGDB", 0, 0>>
  @magic_size byte_size(@magic)
  @version 1

  @max_u32 0xFFFF_FFFF
  @max_u64 0xFFFF_FFFF_FFFF_FFFF

  @type t :: %__MODULE__{
          record_format_id: binary(),
          fingerprint_format_id: binary(),
          fingerprint_size: pos_integer(),
          canonical_bucket_count: pos_integer(),
          position_bucket_count: pos_integer()
        }

  defstruct [
    :record_format_id,
    :fingerprint_format_id,
    :fingerprint_size,
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

      fingerprint_format_id_size =
        byte_size(manifest.fingerprint_format_id)

      {:ok,
       <<
         @magic::binary,
         @version::unsigned-big-16,
         manifest.fingerprint_size::unsigned-big-32,
         manifest.canonical_bucket_count::unsigned-big-64,
         manifest.position_bucket_count::unsigned-big-64,
         record_format_id_size::unsigned-big-32,
         fingerprint_format_id_size::unsigned-big-32,
         manifest.record_format_id::binary,
         manifest.fingerprint_format_id::binary
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
        fingerprint_size::unsigned-big-32,
        canonical_bucket_count::unsigned-big-64,
        position_bucket_count::unsigned-big-64,
        record_format_id_size::unsigned-big-32,
        fingerprint_format_id_size::unsigned-big-32,
        formats::binary
      >> ->
        decode_manifest(
          magic,
          version,
          fingerprint_size,
          canonical_bucket_count,
          position_bucket_count,
          record_format_id_size,
          fingerprint_format_id_size,
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
         _fingerprint_size,
         _canonical_bucket_count,
         _position_bucket_count,
         _record_format_id_size,
         _fingerprint_format_id_size,
         _formats
       )
       when magic != @magic do
    {:error, :invalid_manifest_magic}
  end

  defp decode_manifest(
         @magic,
         version,
         _fingerprint_size,
         _canonical_bucket_count,
         _position_bucket_count,
         _record_format_id_size,
         _fingerprint_format_id_size,
         _formats
       )
       when version != @version do
    {:error, {:unsupported_manifest_version, version}}
  end

  defp decode_manifest(
         @magic,
         @version,
         fingerprint_size,
         canonical_bucket_count,
         position_bucket_count,
         record_format_id_size,
         fingerprint_format_id_size,
         formats
       ) do
    expected_size =
      record_format_id_size +
        fingerprint_format_id_size

    if byte_size(formats) == expected_size do
      <<
        record_format_id::binary-size(^record_format_id_size),
        fingerprint_format_id::binary-size(^fingerprint_format_id_size)
      >> = formats

      manifest = %__MODULE__{
        record_format_id: record_format_id,
        fingerprint_format_id: fingerprint_format_id,
        fingerprint_size: fingerprint_size,
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
         fingerprint_format_id: fingerprint_format_id,
         fingerprint_size: fingerprint_size,
         canonical_bucket_count: canonical_bucket_count,
         position_bucket_count: position_bucket_count
       })
       when is_binary(record_format_id) and byte_size(record_format_id) > 0 and
              byte_size(record_format_id) <= @max_u32 and is_binary(fingerprint_format_id) and
              byte_size(fingerprint_format_id) > 0 and
              byte_size(fingerprint_format_id) <= @max_u32 and is_integer(fingerprint_size) and
              fingerprint_size > 0 and fingerprint_size <= @max_u32 and
              is_integer(canonical_bucket_count) and canonical_bucket_count > 0 and
              canonical_bucket_count <= @max_u64 and is_integer(position_bucket_count) and
              position_bucket_count > 0 and position_bucket_count <= @max_u64 do
    :ok
  end

  defp validate(%__MODULE__{}) do
    {:error, :invalid_manifest}
  end
end
