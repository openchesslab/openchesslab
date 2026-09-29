defmodule GameDB.Storage.Disk.GameInsertMarker do
  @moduledoc """
  Persists the recovery information for one in-flight complete game insert.

  The marker spans both canonical game storage and occurrence storage.

  It is made durable before the canonical game is written and is removed
  durably only after both the canonical game and all of its occurrences
  have been persisted.

  Its presence therefore means outer game-insert recovery is required.
  """

  @filename "game-insert.pending"
  @magic <<"OCLGIN01">>

  @max_id 0xFFFF_FFFF_FFFF_FFFF
  @max_count 0xFFFF_FFFF

  @type entry :: %{
          game_id: pos_integer(),
          position_ids: [pos_integer()]
        }

  @spec create(
          Path.t(),
          pos_integer(),
          [pos_integer()]
        ) ::
          :ok
          | {:error, :append_marker_exists}
          | {:error, term()}
  def create(directory, game_id, position_ids) when is_binary(directory) do
    with :ok <-
           validate(
             game_id,
             position_ids
           ),
         encoded =
           encode(
             game_id,
             position_ids
           ),
         :ok <-
           create_file(
             marker_path(directory),
             encoded
           ) do
      sync_directory(directory)
    end
  end

  @spec read(Path.t()) ::
          {:ok, entry()}
          | :none
          | {:error, :invalid_game_insert_marker}
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

  defp validate(game_id, position_ids) do
    with :ok <-
           validate_game_id(game_id) do
      validate_position_ids(position_ids)
    end
  end

  defp validate_game_id(game_id)
       when is_integer(game_id) and game_id > 0 and game_id <= @max_id do
    :ok
  end

  defp validate_game_id(_game_id) do
    {:error, :invalid_game_id}
  end

  defp validate_position_ids([]) do
    {:error, :missing_initial_position}
  end

  defp validate_position_ids(position_ids) when is_list(position_ids) do
    count =
      length(position_ids)

    cond do
      count > @max_count ->
        {:error, :too_many_occurrences}

      Enum.all?(
        position_ids,
        fn position_id ->
          is_integer(position_id) and
            position_id > 0 and
              position_id <= @max_id
        end
      ) ->
        :ok

      true ->
        {:error, :invalid_position_ids}
    end
  end

  defp validate_position_ids(_position_ids) do
    {:error, :invalid_position_ids}
  end

  defp encode(game_id, position_ids) do
    encoded_position_ids =
      for position_id <- position_ids,
          into: <<>> do
        <<
          position_id::unsigned-big-64
        >>
      end

    <<
      @magic::binary,
      game_id::unsigned-big-64,
      length(position_ids)::unsigned-big-32,
      encoded_position_ids::binary
    >>
  end

  defp decode(
         <<@magic::binary, game_id::unsigned-big-64, count::unsigned-big-32,
           encoded_position_ids::binary>>
       )
       when game_id > 0 and count > 0 do
    expected_size =
      count * 8

    if byte_size(encoded_position_ids) ==
         expected_size do
      case decode_position_ids(
             encoded_position_ids,
             []
           ) do
        {:ok, position_ids} ->
          {:ok,
           %{
             game_id: game_id,
             position_ids: position_ids
           }}

        :error ->
          {:error, :invalid_game_insert_marker}
      end
    else
      {:error, :invalid_game_insert_marker}
    end
  end

  defp decode(_encoded) do
    {:error, :invalid_game_insert_marker}
  end

  defp decode_position_ids(<<>>, reversed) do
    {:ok, Enum.reverse(reversed)}
  end

  defp decode_position_ids(<<position_id::unsigned-big-64, rest::binary>>, reversed)
       when position_id > 0 do
    decode_position_ids(
      rest,
      [
        position_id
        | reversed
      ]
    )
  end

  defp decode_position_ids(_encoded, _reversed) do
    :error
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

  defp marker_path(directory) do
    Path.join(
      directory,
      @filename
    )
  end

  defp sync_directory(directory) do
    case :os.type() do
      {:unix, _name} ->
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

      {:win32, _name} ->
        :ok
    end
  end
end
