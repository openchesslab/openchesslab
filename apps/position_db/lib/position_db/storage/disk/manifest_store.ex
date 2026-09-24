defmodule PositionDB.Storage.Disk.ManifestStore do
  @moduledoc """
  Persists and reads the immutable disk storage manifest.

  A manifest is created once for a disk store. An existing
  manifest is never overwritten.
  """

  alias PositionDB.Storage.Disk.Durability
  alias PositionDB.Storage.Disk.Manifest

  @manifest_filename "manifest.dat"

  @spec create(Path.t(), Manifest.t()) ::
          :ok
          | {:error, :manifest_exists}
          | {:error, term()}
  def create(
        directory,
        %Manifest{} = manifest
      )
      when is_binary(directory) do
    with {:ok, encoded} <-
           Manifest.encode(manifest),
         :ok <-
           create_file(
             manifest_path(directory),
             encoded
           ),
         :ok <-
           Durability.sync_directory(directory) do
      :ok
    end
  end

  @spec read(Path.t()) ::
          {:ok, Manifest.t()}
          | {:error, :manifest_not_found}
          | {:error, term()}
  def read(directory)
      when is_binary(directory) do
    case File.read(manifest_path(directory)) do
      {:ok, encoded} ->
        Manifest.decode(encoded)

      {:error, :enoent} ->
        {:error, :manifest_not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp manifest_path(directory) do
    Path.join(
      directory,
      @manifest_filename
    )
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
                 ),
               :ok <-
                 :file.sync(file) do
            :ok
          end
        after
          :file.close(file)
        end

      {:error, :eexist} ->
        {:error, :manifest_exists}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
