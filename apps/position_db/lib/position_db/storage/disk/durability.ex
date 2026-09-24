defmodule PositionDB.Storage.Disk.Durability do
  @moduledoc """
  Provides durable filesystem transitions for disk storage.

  On Unix systems, directory metadata is explicitly synced after
  operations that create or rename directory entries.

  Windows is supported as a development platform, but the durable
  filesystem guarantees of disk storage target Linux.
  """

  @spec sync_directory(Path.t()) ::
          :ok
          | {:error, term()}
  def sync_directory(directory)
      when is_binary(directory) do
    with :ok <-
           validate_directory(directory) do
      case :os.type() do
        {:unix, _name} ->
          sync_unix_directory(directory)

        {:win32, _name} ->
          :ok
      end
    end
  end

  @spec create_directory(Path.t()) ::
          :ok
          | {:error, term()}
  def create_directory(directory)
      when is_binary(directory) do
    with :ok <-
           File.mkdir(directory),
         :ok <-
           sync_directory(Path.dirname(directory)) do
      :ok
    end
  end

  @spec remove_directory(Path.t()) ::
          :ok
          | {:error, term()}
  def remove_directory(directory)
      when is_binary(directory) do
    parent =
      Path.dirname(directory)

    case File.rm_rf(directory) do
      {:ok, _paths} ->
        sync_directory(parent)

      {:error, reason, path} ->
        {:error, {:remove_directory_failed, path, reason}}
    end
  end

  @doc """
  Renames two sibling paths and durably persists the directory
  entry change.

  Exact-index lifecycle directories are deliberately siblings,
  keeping the rename on the same parent directory.
  """
  @spec rename_sibling(
          Path.t(),
          Path.t()
        ) ::
          :ok
          | {:error, term()}
  def rename_sibling(
        source,
        destination
      )
      when is_binary(source) and
             is_binary(destination) do
    parent =
      Path.dirname(source)

    if parent ==
         Path.dirname(destination) do
      with :ok <-
             File.rename(
               source,
               destination
             ),
           :ok <-
             sync_directory(parent) do
        :ok
      end
    else
      {:error, :different_parent_directories}
    end
  end

  @doc """
  Atomically replaces a sibling regular file on Unix and durably
  persists the directory entry change.

  On Windows the destination is removed first because replacing an
  existing file with rename is not consistently supported. Disk
  durability guarantees target Linux; the Windows path exists for
  development compatibility.
  """
  @spec replace_sibling_file(
          Path.t(),
          Path.t()
        ) ::
          :ok
          | {:error, term()}
  def replace_sibling_file(
        source,
        destination
      )
      when is_binary(source) and
             is_binary(destination) do
    parent =
      Path.dirname(source)

    if parent ==
         Path.dirname(destination) do
      with :ok <-
             validate_regular_file(source),
           :ok <-
             validate_replacement_destination(destination),
           :ok <-
             replace_file(
               source,
               destination
             ),
           :ok <-
             sync_directory(parent) do
        :ok
      end
    else
      {:error, :different_parent_directories}
    end
  end

  @spec sync_file(Path.t()) ::
          :ok
          | {:error, term()}
  def sync_file(path)
      when is_binary(path) do
    with :ok <-
           validate_regular_file(path) do
      case :file.open(
             path,
             [
               :read,
               :write,
               :binary,
               :raw
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

  defp validate_directory(directory) do
    case File.stat(directory) do
      {:ok, %{type: :directory}} ->
        :ok

      {:ok, _stat} ->
        {:error, :not_a_directory}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_regular_file(path) do
    case File.stat(path) do
      {:ok, %{type: :regular}} ->
        :ok

      {:ok, _stat} ->
        {:error, :not_a_regular_file}

      {:error, reason} ->
        {:error, reason}
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

  defp validate_replacement_destination(path) do
    case File.stat(path) do
      {:ok, %{type: :regular}} ->
        :ok

      {:ok, _stat} ->
        {:error, :not_a_regular_file}

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp replace_file(
         source,
         destination
       ) do
    case :os.type() do
      {:unix, _name} ->
        File.rename(
          source,
          destination
        )

      {:win32, _name} ->
        replace_file_windows(
          source,
          destination
        )
    end
  end

  defp replace_file_windows(
         source,
         destination
       ) do
    with :ok <-
           remove_replacement_destination(destination),
         :ok <-
           File.rename(
             source,
             destination
           ) do
      :ok
    end
  end

  defp remove_replacement_destination(path) do
    case File.rm(path) do
      :ok ->
        :ok

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end
end
