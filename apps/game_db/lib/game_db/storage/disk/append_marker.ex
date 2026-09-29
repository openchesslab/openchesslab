defmodule GameDB.Storage.Disk.AppendMarker do
  @moduledoc """
  Persists the game ID of the single in-flight disk append.

  The marker is made durable before the canonical game record is
  written. It is removed durably only after all append effects,
  including secondary indexes, have been persisted.

  Its presence therefore means append recovery is required.
  """

  @filename "append.pending"

  @max_game_id 0xFFFF_FFFF_FFFF_FFFF

  @spec create(Path.t(), pos_integer()) ::
          :ok
          | {:error, :append_marker_exists}
          | {:error, term()}
  def create(directory, game_id)
      when is_binary(directory) and is_integer(game_id) and game_id > 0 and game_id <= @max_game_id do
    with :ok <-
           create_file(
             marker_path(directory),
             encode(game_id)
           ) do
      sync_directory(directory)
    end
  end

  @spec read(Path.t()) ::
          {:ok, pos_integer()}
          | :none
          | {:error, :invalid_append_marker}
          | {:error, term()}
  def read(directory) when is_binary(directory) do
    case File.read(marker_path(directory)) do
      {:ok, encoded} ->
        decode(encoded)

      {:error, :enoent} ->
        :none

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec clear(Path.t()) ::
          :ok
          | {:error, term()}
  def clear(directory) when is_binary(directory) do
    case File.rm(marker_path(directory)) do
      :ok ->
        sync_directory(directory)

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_file(path, encoded) do
    case :file.open(
           path,
           [
             :write,
             :binary,
             :raw,
             :exclusive
           ]
         ) do
      {:ok, file} ->
        try do
          with :ok <-
                 :file.write(
                   file,
                   encoded
                 ) do
            :file.sync(file)
          end
        after
          :file.close(file)
        end

      {:error, :eexist} ->
        {:error, :append_marker_exists}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp encode(game_id) do
    <<
      game_id::unsigned-big-64
    >>
  end

  defp decode(<<game_id::unsigned-big-64>>) when game_id > 0 do
    {:ok, game_id}
  end

  defp decode(_encoded) do
    {:error, :invalid_append_marker}
  end

  defp marker_path(directory) do
    Path.join(
      directory,
      @filename
    )
  end

  defp sync_directory(directory) do
    case :os.type() do
      {:unix, _name} ->
        sync_unix_directory(directory)

      {:win32, _name} ->
        :ok
    end
  end

  defp sync_unix_directory(directory) do
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
  end
end
