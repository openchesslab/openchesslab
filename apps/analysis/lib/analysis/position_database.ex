defmodule Analysis.PositionDatabase do
  @moduledoc false

  alias Analysis.PositionExactKeyHash
  alias Analysis.PositionPropertyKeyCodec
  alias Analysis.PositionRecordCodec

  alias Chess.PositionKey
  alias Chess.PositionProperties

  alias PositionDB.PropertyIndex
  alias PositionDB.PropertyIndex.Disk, as: PropertyIndexDisk
  alias PositionDB.PropertyIndex.Disk.CatchUp
  alias PositionDB.Storage.Disk, as: StorageDisk
  alias PositionDB.Storage.Disk.Durability

  @spec create(Path.t(), keyword()) ::
          {:ok, PositionDB.t()}
          | {:error, term()}
  def create(directory, opts)
      when is_binary(directory) do
    records_per_segment =
      Keyword.fetch!(
        opts,
        :records_per_segment
      )

    exact_bucket_count =
      Keyword.fetch!(
        opts,
        :exact_bucket_count
      )

    property_bucket_count =
      Keyword.fetch!(
        opts,
        :property_bucket_count
      )

    with :ok <-
           create_root_directory(directory),
         {:ok, storage} <-
           StorageDisk.create(
             positions_directory(directory),
             codec: PositionRecordCodec,
             records_per_segment: records_per_segment,
             bucket_count: exact_bucket_count,
             hash: PositionExactKeyHash
           ),
         {:ok, property_backend} <-
           PropertyIndexDisk.create(
             property_index_directory(directory),
             codec: PositionPropertyKeyCodec,
             bucket_count: property_bucket_count
           ) do
      {:ok,
       build_db(
         storage,
         property_backend
       )}
    end
  end

  @spec open(Path.t()) ::
          {:ok, PositionDB.t()}
          | {:error, term()}
  def open(directory)
      when is_binary(directory) do
    with {:ok, storage} <-
           StorageDisk.open(
             positions_directory(directory),
             codec: PositionRecordCodec,
             hash: PositionExactKeyHash
           ),
         {:ok, property_backend} <-
           PropertyIndexDisk.open(
             property_index_directory(directory),
             codec: PositionPropertyKeyCodec
           ) do
      db =
        build_db(
          storage,
          property_backend
        )

      case CatchUp.run(
             db.store,
             db.indexer
           ) do
        {:ok, indexer} ->
          {:ok,
           %{
             db
             | indexer: indexer
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp build_db(
         storage,
         property_backend
       ) do
    property_index =
      PropertyIndex.new(
        PropertyIndexDisk,
        property_backend
      )

    PositionDB.new(
      key_function: &PositionKey.exact/1,
      properties: properties(),
      storage: {
        StorageDisk,
        storage
      },
      property_index: property_index
    )
  end

  defp properties do
    [
      {
        :open_files,
        &PositionProperties.open_files/1
      },
      {
        :material,
        &PositionProperties.material/1
      }
    ]
  end

  defp create_root_directory(directory) do
    case Durability.create_directory(directory) do
      :ok ->
        :ok

      {:error, :eexist} ->
        {:error, :position_database_exists}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp positions_directory(directory) do
    Path.join(
      directory,
      "positions"
    )
  end

  defp property_index_directory(directory) do
    Path.join(
      directory,
      "property-index"
    )
  end
end
