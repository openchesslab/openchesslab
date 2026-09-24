defmodule PositionDB.Storage.Disk.AppendMarker do
  @moduledoc """
  Persists the position ID of the single in-flight disk append.

  The marker is made durable before the position record is written.
  It is removed durably only after all append effects have been
  persisted.

  Its presence therefore means that append recovery is required.
  """

  alias PositionDB.Storage.Disk.Durability

  @filename "append.pending"

  @max_position_id 18_446_744_073_709_551_615

  @spec create(Path.t(), pos_integer()) ::
          :ok
          | {:error, :append_marker_exists}
          | {:error, term()}
  def create(
        directory,
        position_id
      )
      when is_binary(directory) and
             is_integer(position_id) and
             position_id > 0 and
             position_id <= @max_position_id do
    with :ok <-
           create_file(
             marker_path(directory),
             encode(position_id)
           ),
         :ok <-
           Durability.sync_directory(directory) do
      :ok
    end
  end

  @spec read(Path.t()) ::
          {:ok, pos_integer()}
          | :none
          | {:error, :invalid_append_marker}
          | {:error, term()}
  def read(directory)
      when is_binary(directory) do
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
  def clear(directory)
      when is_binary(directory) do
    case File.rm(marker_path(directory)) do
      :ok ->
        Durability.sync_directory(directory)

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_file(
         path,
         encoded
       ) do
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
                 ),
               :ok <-
                 :file.sync(file) do
            :ok
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

  defp encode(position_id) do
    <<
      position_id::unsigned-big-64
    >>
  end

  defp decode(<<
         position_id::unsigned-big-64
       >>)
       when position_id > 0 do
    {:ok, position_id}
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
end
