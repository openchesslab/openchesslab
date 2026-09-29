defmodule Analysis.GameDatabase do
  @moduledoc false

  alias Analysis.GameContentCodec
  alias Analysis.GameFingerprint
  alias GameDB.Storage.Disk

  @spec open_or_create(Path.t(), keyword()) ::
          {:ok, GameDB.t()}
          | {:error, term()}
  def open_or_create(directory, opts) when is_binary(directory) do
    case File.stat(directory) do
      {:ok, %{type: :directory}} ->
        open(directory)

      {:ok, _stat} ->
        {:error, :invalid_game_database_directory}

      {:error, :enoent} ->
        create(
          directory,
          opts
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec create(Path.t(), keyword()) ::
          {:ok, GameDB.t()}
          | {:error, term()}
  def create(directory, opts) when is_binary(directory) do
    bucket_count =
      Keyword.fetch!(
        opts,
        :bucket_count
      )

    position_bucket_count =
      Keyword.fetch!(
        opts,
        :position_bucket_count
      )

    with {:ok, storage} <-
           Disk.create(
             directory,
             codec: GameContentCodec,
             fingerprint_format_id: GameFingerprint.format_id(),
             fingerprint_size: GameFingerprint.fingerprint_size(),
             bucket_count: bucket_count,
             position_bucket_count: position_bucket_count
           ) do
      {:ok,
       GameDB.new(
         Disk,
         storage
       )}
    end
  end

  @spec open(Path.t()) ::
          {:ok, GameDB.t()}
          | {:error, term()}
  def open(directory) when is_binary(directory) do
    with {:ok, storage} <-
           Disk.open(
             directory,
             codec: GameContentCodec,
             fingerprint_format_id: GameFingerprint.format_id(),
             fingerprint_size: GameFingerprint.fingerprint_size()
           ) do
      {:ok,
       GameDB.new(
         Disk,
         storage
       )}
    end
  end
end
