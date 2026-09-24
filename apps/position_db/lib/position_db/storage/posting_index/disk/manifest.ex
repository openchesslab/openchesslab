defmodule PositionDB.Storage.PostingIndex.Disk.Manifest do
  @moduledoc """
  Durable description of a disk-backed posting index.

  The manifest records the key format and physical bucket layout
  required to interpret an existing posting index.

  Manifest version 1 identifies the current posting-index physical
  format, including SHA-256 bucket selection and the variable-size
  posting entry layout.
  """

  @magic <<"OCLPIX", 0, 0>>
  @magic_size byte_size(@magic)

  @version 1

  @max_u32 4_294_967_295
  @max_u64 18_446_744_073_709_551_615

  @type t :: %__MODULE__{
          key_format_id: binary(),
          bucket_count: pos_integer()
        }

  defstruct [
    :key_format_id,
    :bucket_count
  ]

  @spec encode(t()) ::
          {:ok, binary()}
          | {:error, :invalid_posting_manifest}
  def encode(%__MODULE__{} = manifest) do
    with :ok <-
           validate(manifest) do
      key_format_id_size =
        byte_size(manifest.key_format_id)

      {:ok,
       <<
         @magic::binary,
         @version::unsigned-big-16,
         manifest.bucket_count::unsigned-big-64,
         key_format_id_size::unsigned-big-32,
         manifest.key_format_id::binary
       >>}
    end
  end

  @spec decode(binary()) ::
          {:ok, t()}
          | {:error, :invalid_posting_manifest}
          | {:error, :invalid_posting_manifest_magic}
          | {:error, :invalid_posting_manifest_size}
          | {:error, {:unsupported_posting_manifest_version, non_neg_integer()}}
  def decode(encoded)
      when is_binary(encoded) do
    case encoded do
      <<
        magic::binary-size(@magic_size),
        version::unsigned-big-16,
        bucket_count::unsigned-big-64,
        key_format_id_size::unsigned-big-32,
        key_format_id::binary
      >> ->
        decode_manifest(
          magic,
          version,
          bucket_count,
          key_format_id_size,
          key_format_id
        )

      _other ->
        {:error, :invalid_posting_manifest}
    end
  end

  def decode(_encoded) do
    {:error, :invalid_posting_manifest}
  end

  defp decode_manifest(
         magic,
         _version,
         _bucket_count,
         _key_format_id_size,
         _key_format_id
       )
       when magic != @magic do
    {:error, :invalid_posting_manifest_magic}
  end

  defp decode_manifest(
         @magic,
         version,
         _bucket_count,
         _key_format_id_size,
         _key_format_id
       )
       when version != @version do
    {:error, {:unsupported_posting_manifest_version, version}}
  end

  defp decode_manifest(
         @magic,
         @version,
         bucket_count,
         key_format_id_size,
         key_format_id
       ) do
    if byte_size(key_format_id) ==
         key_format_id_size do
      manifest =
        %__MODULE__{
          key_format_id: key_format_id,
          bucket_count: bucket_count
        }

      case validate(manifest) do
        :ok ->
          {:ok, manifest}

        {:error, :invalid_posting_manifest} ->
          {:error, :invalid_posting_manifest}
      end
    else
      {:error, :invalid_posting_manifest_size}
    end
  end

  defp validate(%__MODULE__{
         key_format_id: key_format_id,
         bucket_count: bucket_count
       })
       when is_binary(key_format_id) and
              byte_size(key_format_id) > 0 and
              byte_size(key_format_id) <= @max_u32 and
              is_integer(bucket_count) and
              bucket_count > 0 and
              bucket_count <= @max_u64 do
    :ok
  end

  defp validate(%__MODULE__{}) do
    {:error, :invalid_posting_manifest}
  end
end
