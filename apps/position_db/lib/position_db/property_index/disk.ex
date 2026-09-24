defmodule PositionDB.PropertyIndex.Disk do
  @moduledoc """
  Persistent property index backed by a disk posting index.

  Logical property keys are encoded by the configured property-key
  codec before they are stored in the posting index.

  The durable progress watermark is advanced separately from posting
  writes. Callers must only advance it after all property postings for
  that position ID are durable.
  """

  alias PositionDB.Storage.Disk.Durability
  alias PositionDB.Storage.Disk.IndexProgressStore
  alias PositionDB.Storage.PostingIndex.Disk, as: PostingIndex
  alias PositionDB.Storage.PostingIndex.Disk.Manifest
  alias PositionDB.Storage.PostingIndex.Disk.ManifestStore

  @type property :: {atom(), term()}

  @type t :: %__MODULE__{
          directory: Path.t(),
          posting_index: PostingIndex.t(),
          codec_module: module(),
          indexed_through_id: non_neg_integer()
        }

  defstruct [
    :directory,
    :posting_index,
    :codec_module,
    indexed_through_id: 0
  ]

  @spec create(Path.t(), keyword()) ::
          {:ok, t()}
          | {:error, :property_index_exists}
          | {:error, term()}
  def create(directory, opts)
      when is_binary(directory) do
    codec_module =
      Keyword.fetch!(
        opts,
        :codec
      )

    bucket_count =
      Keyword.fetch!(
        opts,
        :bucket_count
      )

    manifest =
      %Manifest{
        key_format_id: codec_module.format_id(),
        bucket_count: bucket_count
      }

    with {:ok, _encoded} <-
           Manifest.encode(manifest),
         :ok <-
           create_root_directory(directory),
         :ok <-
           ManifestStore.create(
             directory,
             manifest
           ),
         :ok <-
           IndexProgressStore.advance(
             directory,
             0
           ) do
      {:ok,
       build(
         directory,
         codec_module,
         bucket_count,
         0
       )}
    end
  end

  @spec open(Path.t(), keyword()) ::
          {:ok, t()}
          | {:error, term()}
  def open(directory, opts)
      when is_binary(directory) do
    codec_module =
      Keyword.fetch!(
        opts,
        :codec
      )

    with {:ok, manifest} <-
           ManifestStore.read(directory),
         :ok <-
           validate_runtime_format(
             manifest,
             codec_module
           ),
         {:ok, indexed_through_id} <-
           read_progress(directory) do
      {:ok,
       build(
         directory,
         codec_module,
         manifest.bucket_count,
         indexed_through_id
       )}
    end
  end

  @spec add(
          t(),
          property(),
          pos_integer()
        ) ::
          {:ok, t()}
          | {:error, term()}
  def add(
        %__MODULE__{} = index,
        property,
        position_id
      )
      when is_integer(position_id) and
             position_id > 0 do
    with {:ok, key} <-
           encode_property(
             index,
             property
           ),
         {:ok, posting_index} <-
           PostingIndex.add(
             index.posting_index,
             key,
             position_id
           ) do
      {:ok,
       %{
         index
         | posting_index: posting_index
       }}
    end
  end

  @doc """
  Recovers or completes one posting while replaying an incompletely
  indexed position.

  Unlike `add/3`, this operation can repair a matching partial posting
  tail left by an interrupted durable append.
  """
  @spec recover_add(
          t(),
          property(),
          pos_integer()
        ) ::
          {:ok, t()}
          | {:error, term()}
  def recover_add(
        %__MODULE__{} = index,
        property,
        position_id
      )
      when is_integer(position_id) and
             position_id > 0 do
    with {:ok, key} <-
           encode_property(
             index,
             property
           ),
         :ok <-
           PostingIndex.recover_pending_append(
             index.posting_index,
             key,
             position_id
           ) do
      {:ok, index}
    end
  end

  @spec lookup(
          t(),
          property()
        ) ::
          {:ok, [pos_integer()]}
          | {:error, term()}
  def lookup(
        %__MODULE__{} = index,
        property
      ) do
    with {:ok, key} <-
           encode_property(
             index,
             property
           ) do
      PostingIndex.lookup(
        index.posting_index,
        key
      )
    end
  end

  @spec cardinality(
          t(),
          property()
        ) ::
          {:ok, non_neg_integer()}
          | {:error, term()}
  def cardinality(
        %__MODULE__{} = index,
        property
      ) do
    with {:ok, key} <-
           encode_property(
             index,
             property
           ) do
      PostingIndex.cardinality(
        index.posting_index,
        key
      )
    end
  end

  @spec indexed_through(t()) ::
          non_neg_integer()
  def indexed_through(%__MODULE__{
        indexed_through_id: indexed_through_id
      }) do
    indexed_through_id
  end

  @spec advance(
          t(),
          non_neg_integer()
        ) ::
          {:ok, t()}
          | {:error, term()}
  def advance(
        %__MODULE__{} = index,
        indexed_through_id
      )
      when is_integer(indexed_through_id) and
             indexed_through_id >= 0 do
    with :ok <-
           IndexProgressStore.advance(
             index.directory,
             indexed_through_id
           ) do
      {:ok,
       %{
         index
         | indexed_through_id: indexed_through_id
       }}
    end
  end

  defp build(
         directory,
         codec_module,
         bucket_count,
         indexed_through_id
       ) do
    %__MODULE__{
      directory: directory,
      posting_index:
        PostingIndex.new(
          directory,
          bucket_count: bucket_count
        ),
      codec_module: codec_module,
      indexed_through_id: indexed_through_id
    }
  end

  defp encode_property(
         %__MODULE__{
           codec_module: codec_module
         },
         {name, value}
       )
       when is_atom(name) do
    case codec_module.encode(
           name,
           value
         ) do
      {:ok, key}
      when is_binary(key) ->
        {:ok, key}

      {:ok, _key} ->
        {:error, :invalid_property_key}

      {:error, reason} ->
        {:error, reason}

      _other ->
        {:error, :invalid_property_key}
    end
  end

  defp encode_property(
         %__MODULE__{},
         _property
       ) do
    {:error, :invalid_property}
  end

  defp validate_runtime_format(
         %Manifest{} = manifest,
         codec_module
       ) do
    configured =
      codec_module.format_id()

    if manifest.key_format_id ==
         configured do
      :ok
    else
      {:error,
       {:property_index_format_mismatch, :key_format_id, manifest.key_format_id, configured}}
    end
  end

  defp read_progress(directory) do
    case IndexProgressStore.read(directory) do
      {:ok, indexed_through_id} ->
        {:ok, indexed_through_id}

      :none ->
        {:error, :property_index_progress_not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_root_directory(directory) do
    case Durability.create_directory(directory) do
      :ok ->
        :ok

      {:error, :eexist} ->
        {:error, :property_index_exists}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
