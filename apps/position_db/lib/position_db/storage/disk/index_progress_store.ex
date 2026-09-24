defmodule PositionDB.Storage.Disk.IndexProgressStore do
  @moduledoc """
  Persists the durable progress watermark of a derived index.

  `indexed_through_id` identifies the highest position ID for
  which all index effects are known to be durable.

  Progress is monotonic. Updating it writes and syncs a temporary
  file before atomically replacing the active progress file.
  """

  alias PositionDB.Storage.Disk.Durability

  @magic <<"OCLIDX", 0, 0>>
  @magic_size byte_size(@magic)

  @version 1

  @filename "indexed-through.dat"
  @next_filename "indexed-through.next"

  @max_position_id 18_446_744_073_709_551_615

  @type indexed_through_id :: non_neg_integer()

  @spec read(Path.t()) ::
          {:ok, indexed_through_id()}
          | :none
          | {:error, :invalid_index_progress}
          | {:error, :invalid_index_progress_magic}
          | {:error, {:unsupported_index_progress_version, non_neg_integer()}}
          | {:error, term()}
  def read(directory)
      when is_binary(directory) do
    case File.read(progress_path(directory)) do
      {:ok, encoded} ->
        decode(encoded)

      {:error, :enoent} ->
        :none

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec advance(
          Path.t(),
          indexed_through_id()
        ) ::
          :ok
          | {:error, {:indexed_through_regression, indexed_through_id(), indexed_through_id()}}
          | {:error, term()}
  def advance(
        directory,
        indexed_through_id
      )
      when is_binary(directory) and
             is_integer(indexed_through_id) and
             indexed_through_id >= 0 and
             indexed_through_id <= @max_position_id do
    case read(directory) do
      :none ->
        persist(
          directory,
          indexed_through_id
        )

      {:ok, current}
      when indexed_through_id < current ->
        {:error, {:indexed_through_regression, current, indexed_through_id}}

      {:ok, ^indexed_through_id} ->
        :ok

      {:ok, _current} ->
        persist(
          directory,
          indexed_through_id
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp persist(
         directory,
         indexed_through_id
       ) do
    next =
      next_path(directory)

    active =
      progress_path(directory)

    with :ok <-
           remove_stale_next(next),
         :ok <-
           create_next(
             next,
             encode(indexed_through_id)
           ),
         :ok <-
           Durability.replace_sibling_file(
             next,
             active
           ) do
      :ok
    end
  end

  defp create_next(
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

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp remove_stale_next(path) do
    case File.rm(path) do
      :ok ->
        :ok

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp encode(indexed_through_id) do
    <<
      @magic::binary,
      @version::unsigned-big-16,
      indexed_through_id::unsigned-big-64
    >>
  end

  defp decode(encoded)
       when is_binary(encoded) do
    case encoded do
      <<
        magic::binary-size(@magic_size),
        version::unsigned-big-16,
        indexed_through_id::unsigned-big-64
      >> ->
        decode_progress(
          magic,
          version,
          indexed_through_id
        )

      _other ->
        {:error, :invalid_index_progress}
    end
  end

  defp decode_progress(
         magic,
         _version,
         _indexed_through_id
       )
       when magic != @magic do
    {:error, :invalid_index_progress_magic}
  end

  defp decode_progress(
         @magic,
         version,
         _indexed_through_id
       )
       when version != @version do
    {:error, {:unsupported_index_progress_version, version}}
  end

  defp decode_progress(
         @magic,
         @version,
         indexed_through_id
       ) do
    {:ok, indexed_through_id}
  end

  defp progress_path(directory) do
    Path.join(
      directory,
      @filename
    )
  end

  defp next_path(directory) do
    Path.join(
      directory,
      @next_filename
    )
  end
end
