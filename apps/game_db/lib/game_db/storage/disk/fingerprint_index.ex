defmodule GameDB.Storage.Disk.FingerprintIndex do
  @moduledoc """
  Disk-backed index from canonical game fingerprints to candidate game IDs.

  Fingerprints are distributed across bucket files using their first
  32 bits. Each bucket stores fixed-size entries containing the complete
  fingerprint and an unsigned 64-bit game ID.

  The complete fingerprint is compared during lookup, so bucket
  collisions cannot affect lookup semantics.
  """

  @fingerprint_size 32
  @game_id_size 8
  @entry_size @fingerprint_size + @game_id_size
  @max_game_id 0xFFFF_FFFF_FFFF_FFFF

  @type t :: %__MODULE__{
          directory: Path.t(),
          bucket_count: pos_integer()
        }

  defstruct [
    :directory,
    :bucket_count
  ]

  @spec new(Path.t(), keyword()) :: t()
  def new(directory, opts)
      when is_binary(directory) do
    bucket_count =
      Keyword.fetch!(
        opts,
        :bucket_count
      )

    if bucket_count <= 0 do
      raise ArgumentError,
            "bucket_count must be positive"
    end

    %__MODULE__{
      directory: directory,
      bucket_count: bucket_count
    }
  end

  @spec lookup(t(), binary()) ::
          {:ok, [pos_integer()]}
          | {:error, term()}
  def lookup(
        %__MODULE__{} = index,
        fingerprint
      )
      when is_binary(fingerprint) do
    with :ok <-
           validate_fingerprint(fingerprint) do
      path =
        bucket_path(
          index,
          fingerprint
        )

      lookup_bucket(
        path,
        fingerprint,
        []
      )
    end
  end

  @spec add(
          t(),
          binary(),
          pos_integer()
        ) ::
          {:ok, t()}
          | {:error, term()}
  def add(
        %__MODULE__{} = index,
        fingerprint,
        game_id
      )
      when is_binary(fingerprint) and
             is_integer(game_id) and
             game_id > 0 do
    with :ok <-
           validate_fingerprint(fingerprint),
         :ok <-
           validate_game_id(game_id),
         {:ok, candidates} <-
           lookup(
             index,
             fingerprint
           ) do
      if game_id in candidates do
        {:ok, index}
      else
        path =
          bucket_path(
            index,
            fingerprint
          )

        entry =
          encode_entry(
            fingerprint,
            game_id
          )

        case append_entry(
               index,
               path,
               entry
             ) do
          :ok ->
            {:ok, index}

          {:error, reason} ->
            {:error, reason}
        end
      end
    end
  end

  @doc """
  Recovers one interrupted fingerprint-index append.

  If a matching partial entry exists at the end of the bucket, it is
  truncated and the complete entry is written durably.

  If the complete entry already exists, it is left unchanged.

  An unrelated partial tail is never modified.
  """
  @spec recover_pending_append(
          t(),
          binary(),
          pos_integer()
        ) ::
          :ok
          | {:error, term()}
  def recover_pending_append(
        %__MODULE__{} = index,
        fingerprint,
        game_id
      )
      when is_binary(fingerprint) and
             is_integer(game_id) and
             game_id > 0 do
    with :ok <-
           validate_fingerprint(fingerprint),
         :ok <-
           validate_game_id(game_id) do
      path =
        bucket_path(
          index,
          fingerprint
        )

      entry =
        encode_entry(
          fingerprint,
          game_id
        )

      recover_bucket(
        index,
        path,
        fingerprint,
        game_id,
        entry
      )
    end
  end

  defp lookup_bucket(
         path,
         fingerprint,
         reversed_game_ids
       ) do
    case :file.open(
           path,
           [
             :read,
             :binary,
             :raw
           ]
         ) do
      {:ok, file} ->
        try do
          lookup_entries(
            file,
            fingerprint,
            reversed_game_ids
          )
        after
          :file.close(file)
        end

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp lookup_entries(
         file,
         fingerprint,
         reversed_game_ids
       ) do
    case :file.read(
           file,
           @entry_size
         ) do
      {:ok, entry}
      when byte_size(entry) ==
             @entry_size ->
        <<
          stored_fingerprint::binary-size(@fingerprint_size),
          game_id::unsigned-big-64
        >> = entry

        reversed_game_ids =
          if stored_fingerprint ==
               fingerprint do
            [
              game_id
              | reversed_game_ids
            ]
          else
            reversed_game_ids
          end

        lookup_entries(
          file,
          fingerprint,
          reversed_game_ids
        )

      {:ok, _partial_entry} ->
        {:error, :partial_entry}

      :eof ->
        {:ok, Enum.reverse(reversed_game_ids)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp append_entry(
         index,
         path,
         entry
       ) do
    with {:ok, bucket_state} <-
           bucket_state(path) do
      case :file.open(
             path,
             [
               :append,
               :binary,
               :raw
             ]
           ) do
        {:ok, file} ->
          result =
            try do
              with :ok <-
                     :file.write(
                       file,
                       entry
                     ),
                   :ok <-
                     :file.sync(file) do
                :ok
              end
            after
              :file.close(file)
            end

          with :ok <- result,
               :ok <-
                 sync_new_bucket(
                   index,
                   bucket_state
                 ) do
            :ok
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp recover_bucket(
         index,
         path,
         fingerprint,
         game_id,
         entry
       ) do
    case File.stat(path) do
      {:ok, %{size: size}} ->
        partial_size =
          rem(
            size,
            @entry_size
          )

        if partial_size == 0 do
          ensure_entry(
            index,
            path,
            fingerprint,
            game_id,
            entry
          )
        else
          complete_size =
            size -
              partial_size

          with {:ok, partial} <-
                 read_partial_tail(
                   path,
                   complete_size,
                   partial_size
                 ),
               :ok <-
                 validate_partial_entry(
                   partial,
                   entry
                 ),
               :ok <-
                 truncate_bucket(
                   path,
                   complete_size
                 ),
               :ok <-
                 ensure_entry(
                   index,
                   path,
                   fingerprint,
                   game_id,
                   entry
                 ) do
            :ok
          end
        end

      {:error, :enoent} ->
        append_entry(
          index,
          path,
          entry
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ensure_entry(
         index,
         path,
         fingerprint,
         game_id,
         entry
       ) do
    with {:ok, candidates} <-
           lookup(
             index,
             fingerprint
           ) do
      if game_id in candidates do
        sync_file(path)
      else
        append_entry(
          index,
          path,
          entry
        )
      end
    end
  end

  defp bucket_state(path) do
    case File.stat(path) do
      {:ok, %{size: size}} ->
        if rem(
             size,
             @entry_size
           ) == 0 do
          {:ok, :existing}
        else
          {:error, :partial_entry}
        end

      {:error, :enoent} ->
        {:ok, :new}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp bucket_path(
         index,
         fingerprint
       ) do
    bucket =
      bucket(
        fingerprint,
        index.bucket_count
      )

    filename =
      bucket
      |> Integer.to_string()
      |> String.pad_leading(
        8,
        "0"
      )
      |> then(&"bucket-#{&1}.idx")

    Path.join(
      index.directory,
      filename
    )
  end

  defp bucket(
         <<
           prefix::unsigned-big-32,
           _rest::binary
         >>,
         bucket_count
       ) do
    rem(
      prefix,
      bucket_count
    )
  end

  defp encode_entry(
         fingerprint,
         game_id
       ) do
    <<
      fingerprint::binary-size(@fingerprint_size),
      game_id::unsigned-big-64
    >>
  end

  defp validate_fingerprint(fingerprint) do
    if byte_size(fingerprint) ==
         @fingerprint_size do
      :ok
    else
      {:error, :invalid_fingerprint_size}
    end
  end

  defp validate_game_id(game_id)
       when game_id <= @max_game_id do
    :ok
  end

  defp validate_game_id(_game_id) do
    {:error, :invalid_game_id}
  end

  defp read_partial_tail(
         path,
         offset,
         size
       ) do
    case :file.open(
           path,
           [
             :read,
             :binary,
             :raw
           ]
         ) do
      {:ok, file} ->
        try do
          case :file.pread(
                 file,
                 offset,
                 size
               ) do
            {:ok, partial}
            when byte_size(partial) ==
                   size ->
              {:ok, partial}

            {:ok, _partial} ->
              {:error, :partial_entry}

            :eof ->
              {:error, :partial_entry}

            {:error, reason} ->
              {:error, reason}
          end
        after
          :file.close(file)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_partial_entry(
         partial,
         entry
       ) do
    expected =
      binary_part(
        entry,
        0,
        byte_size(partial)
      )

    if partial ==
         expected do
      :ok
    else
      {:error, :unexpected_partial_entry}
    end
  end

  defp truncate_bucket(
         path,
         size
       ) do
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
          with {:ok, ^size} <-
                 :file.position(
                   file,
                   size
                 ),
               :ok <-
                 :file.truncate(file),
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

  defp sync_file(path) do
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

  defp sync_new_bucket(
         index,
         :new
       ) do
    sync_directory(index.directory)
  end

  defp sync_new_bucket(
         _index,
         :existing
       ) do
    :ok
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
