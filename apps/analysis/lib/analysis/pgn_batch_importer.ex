defmodule Analysis.PgnBatchImporter do
  @moduledoc """
  Parses and imports headered multi-game PGN input through the single-game importer.

  The batch boundary identifies individual games and delegates the chess
  semantics of each game to `Analysis.PgnImporter`.

  `import_games/2` is intended for bounded in-memory batches. The complete
  batch is parsed before persistence starts, so parse errors never create
  partial durable imports.

  `import_stream/2` consumes an enumerable of lines one game at a time.
  It retains only the current PGN game in memory and persists each valid
  game before continuing. A later parse or persistence failure therefore
  leaves the successfully imported prefix durable.

  `import_file/2` is the file-backed entry point for strict ordered imports.

  `import_stream_parallel/3` and `import_file_parallel/3` are explicit
  high-throughput boundaries. They process bounded windows of complete games
  concurrently. Every game still owns its own PostgreSQL transaction, but a
  failure does not stop later games from being attempted. Successful imports
  are counted and failures retain their one-based source-game index.

  Parallel import therefore does not provide the successful-prefix semantics
  of `import_stream/2`.

  Concrete game-record identity remains caller-owned. Bounded imports
  receive explicit record IDs; streaming imports receive a function that
  supplies the record ID for each one-based game index.

  Each game in a batch must start with a PGN tag-pair section. Tagless
  single games remain supported directly by `Analysis.PgnImporter`.
  """

  alias Analysis.GameRecord
  alias Analysis.PgnImporter

  @header_line_regex ~r/^\s*\[[A-Za-z0-9_]+\s+"(?:\\.|[^"])*"\]\s*$/

  @type parse_error ::
          :empty_batch
          | :game_headers_required
          | {:invalid_game, pos_integer(), {:invalid_pgn, String.t()}}

  @type import_error ::
          parse_error()
          | {:invalid_record_id, pos_integer()}
          | {:duplicate_record_id, pos_integer()}
          | {:record_id_count_mismatch, non_neg_integer(), non_neg_integer()}
          | {:import_failed, pos_integer(), PgnImporter.import_error()}

  @type stream_import_error ::
          parse_error()
          | :invalid_record_id_provider
          | {:invalid_record_id, pos_integer()}
          | {:import_failed, pos_integer(), PgnImporter.import_error()}

  @type file_import_error ::
          :invalid_path
          | :invalid_record_id_provider
          | {:file, term()}
          | stream_import_error()

  @type parallel_import_failure ::
          {:invalid_game, pos_integer(), {:invalid_pgn, String.t()}}
          | {:invalid_record_id, pos_integer()}
          | {:import_failed, pos_integer(), PgnImporter.import_error()}

  @type parallel_import_error ::
          :empty_batch
          | :game_headers_required
          | :invalid_record_id_provider
          | {:invalid_max_concurrency, term()}
          | {:invalid_window_size, term()}
          | {:parallel_worker_exit, term()}

  @type parallel_file_import_error ::
          :invalid_path
          | :invalid_record_id_provider
          | {:invalid_max_concurrency, term()}
          | {:file, term()}
          | parallel_import_error()

  defmodule ParallelImportResult do
    @moduledoc """
    Result of a completed bounded-parallel import.

    Successful games are counted rather than accumulated so large imports do
    not retain every `GameRecord` in memory. Failures retain their original
    one-based source-game index.
    """

    @enforce_keys [
      :imported_count,
      :failures
    ]

    defstruct imported_count: 0,
              failures: []

    @type t :: %__MODULE__{
            imported_count: non_neg_integer(),
            failures: [Analysis.PgnBatchImporter.parallel_import_failure()]
          }
  end

  @spec parse(String.t()) ::
          {:ok, [PgnImporter.result()]}
          | {:error, parse_error()}
  def parse(pgn) when is_binary(pgn) do
    pgn
    |> String.split(
      ~r/\R/,
      trim: false
    )
    |> parse_lines()
  end

  def parse(_pgn) do
    {:error, :game_headers_required}
  end

  @spec import_games(
          [GameRecord.id()],
          String.t()
        ) ::
          {:ok, [GameRecord.t()]}
          | {:error, import_error()}
  def import_games(record_ids, pgn) when is_list(record_ids) and is_binary(pgn) do
    with :ok <-
           validate_record_ids(record_ids),
         {:ok, parsed_games} <-
           parse(pgn),
         :ok <-
           validate_record_id_count(
             record_ids,
             parsed_games
           ) do
      persist_games(
        record_ids,
        parsed_games
      )
    end
  end

  def import_games(_record_ids, _pgn) do
    {:error, {:invalid_record_id, 1}}
  end

  @spec import_stream(
          Enumerable.t(),
          (pos_integer() -> GameRecord.id())
        ) ::
          {:ok, non_neg_integer()}
          | {:error, stream_import_error()}
  def import_stream(lines, record_id_for_index) when is_function(record_id_for_index, 1) do
    reduce_games(
      lines,
      0,
      fn game, index, imported_count ->
        import_stream_game(
          game,
          index,
          imported_count,
          record_id_for_index
        )
      end
    )
  end

  def import_stream(_lines, _record_id_for_index) do
    {:error, :invalid_record_id_provider}
  end

  @spec import_stream_parallel(
          Enumerable.t(),
          (pos_integer() -> GameRecord.id()),
          pos_integer()
        ) ::
          {:ok, ParallelImportResult.t()}
          | {:error, parallel_import_error()}
  def import_stream_parallel(lines, record_id_for_index, max_concurrency) do
    import_stream_parallel(lines, record_id_for_index, max_concurrency, max_concurrency)
  end

  @doc """
  Parallel import with a bounded game window, independent of worker count.

  A larger window lets idle workers start another queued game instead of
  waiting for the slowest game in a worker-sized wave. At most
  `max_concurrency` games run simultaneously; at most `window_size` PGNs
  are retained in the pending window.
  """
  @spec import_stream_parallel(
          Enumerable.t(),
          (pos_integer() -> GameRecord.id()),
          pos_integer(),
          pos_integer()
        ) ::
          {:ok, ParallelImportResult.t()}
          | {:error, parallel_import_error()}
  def import_stream_parallel(lines, record_id_for_index, max_concurrency, window_size)
      when is_function(record_id_for_index, 1) do
    with :ok <- validate_max_concurrency(max_concurrency),
         :ok <- validate_window_size(window_size, max_concurrency) do
      initial_state = %{
        pending: [],
        imported_count: 0,
        failures: []
      }

      case reduce_games(
             lines,
             initial_state,
             fn game, index, state ->
               queue_parallel_game(
                 game,
                 index,
                 state,
                 record_id_for_index,
                 max_concurrency,
                 window_size
               )
             end
           ) do
        {:ok, state} ->
          case flush_parallel_games(state, record_id_for_index, max_concurrency) do
            {:ok, state} ->
              {:ok,
               %ParallelImportResult{
                 imported_count: state.imported_count,
                 failures: Enum.sort_by(state.failures, &parallel_failure_index/1)
               }}

            {:error, _reason} = error ->
              error
          end

        {:error, _reason} = error ->
          error
      end
    end
  end

  def import_stream_parallel(_lines, _record_id_for_index, _max_concurrency, _window_size) do
    {:error, :invalid_record_id_provider}
  end

  @spec import_file(
          String.t(),
          (pos_integer() -> GameRecord.id())
        ) ::
          {:ok, non_neg_integer()}
          | {:error, file_import_error()}
  def import_file(path, record_id_for_index)
      when is_binary(path) and byte_size(path) > 0 and is_function(record_id_for_index, 1) do
    case File.open(
           path,
           [:read, :utf8],
           fn io ->
             io
             |> IO.stream(:line)
             |> import_stream(record_id_for_index)
           end
         ) do
      {:ok, result} ->
        result

      {:error, reason} ->
        {:error,
         {
           :file,
           reason
         }}
    end
  end

  def import_file(path, _record_id_for_index) when not is_binary(path) do
    {:error, :invalid_path}
  end

  def import_file("", _record_id_for_index) do
    {:error, :invalid_path}
  end

  def import_file(_path, _record_id_for_index) do
    {:error, :invalid_record_id_provider}
  end

  @spec import_file_parallel(
          String.t(),
          (pos_integer() -> GameRecord.id()),
          pos_integer()
        ) ::
          {:ok, ParallelImportResult.t()}
          | {:error, parallel_file_import_error()}
  def import_file_parallel(path, record_id_for_index, max_concurrency) do
    import_file_parallel(path, record_id_for_index, max_concurrency, max_concurrency)
  end

  @spec import_file_parallel(
          String.t(),
          (pos_integer() -> GameRecord.id()),
          pos_integer(),
          pos_integer()
        ) ::
          {:ok, ParallelImportResult.t()}
          | {:error, parallel_file_import_error()}
  def import_file_parallel(path, record_id_for_index, max_concurrency, window_size)
      when is_binary(path) and byte_size(path) > 0 and is_function(record_id_for_index, 1) do
    with :ok <- validate_max_concurrency(max_concurrency),
         :ok <- validate_window_size(window_size, max_concurrency) do
      case File.open(
             path,
             [:read, :utf8],
             fn io ->
               io
               |> IO.stream(:line)
               |> import_stream_parallel(record_id_for_index, max_concurrency, window_size)
             end
           ) do
        {:ok, result} ->
          result

        {:error, reason} ->
          {:error, {:file, reason}}
      end
    end
  end

  def import_file_parallel(path, _record_id_for_index, _max_concurrency, _window_size)
      when not is_binary(path) do
    {:error, :invalid_path}
  end

  def import_file_parallel("", _record_id_for_index, _max_concurrency, _window_size) do
    {:error, :invalid_path}
  end

  def import_file_parallel(_path, _record_id_for_index, _max_concurrency, _window_size) do
    {:error, :invalid_record_id_provider}
  end

  defp parse_lines(lines) do
    case reduce_games(
           lines,
           [],
           &parse_game/3
         ) do
      {:ok, parsed_games} ->
        {:ok, Enum.reverse(parsed_games)}

      {:error, _reason} = error ->
        error
    end
  end

  defp reduce_games(lines, initial_accumulator, on_game) do
    lines
    |> Enum.reduce_while(
      {
        :ok,
        initial_accumulator,
        [],
        :before_game,
        0
      },
      fn line, state ->
        reduce_line(
          normalize_line(line),
          state,
          on_game
        )
      end
    )
    |> finish_reduction(on_game)
  end

  defp reduce_line(line, {:ok, accumulator, current, state, completed_count}, on_game) do
    cond do
      String.trim(line) == "" ->
        reduce_blank_line(
          line,
          accumulator,
          current,
          state,
          completed_count
        )

      header_line?(line) ->
        reduce_header_line(
          line,
          accumulator,
          current,
          state,
          completed_count,
          on_game
        )

      state == :before_game ->
        {:halt,
         {
           :error,
           :game_headers_required
         }}

      true ->
        {:cont,
         {
           :ok,
           accumulator,
           [
             line
             | current
           ],
           :movetext,
           completed_count
         }}
    end
  end

  defp reduce_blank_line(_line, accumulator, [], :before_game, completed_count) do
    {:cont,
     {
       :ok,
       accumulator,
       [],
       :before_game,
       completed_count
     }}
  end

  defp reduce_blank_line(line, accumulator, current, state, completed_count) do
    {:cont,
     {
       :ok,
       accumulator,
       [
         line
         | current
       ],
       state,
       completed_count
     }}
  end

  defp reduce_header_line(line, accumulator, current, :movetext, completed_count, on_game) do
    index =
      completed_count + 1

    case on_game.(
           finish_game(current),
           index,
           accumulator
         ) do
      {:ok, accumulator} ->
        {:cont,
         {
           :ok,
           accumulator,
           [
             line
           ],
           :headers,
           index
         }}

      {:error, reason} ->
        {:halt,
         {
           :error,
           reason
         }}
    end
  end

  defp reduce_header_line(line, accumulator, current, _state, completed_count, _on_game) do
    {:cont,
     {
       :ok,
       accumulator,
       [
         line
         | current
       ],
       :headers,
       completed_count
     }}
  end

  defp finish_reduction({:error, reason}, _on_game) do
    {:error, reason}
  end

  defp finish_reduction({:ok, _accumulator, [], :before_game, 0}, _on_game) do
    {:error, :empty_batch}
  end

  defp finish_reduction({:ok, accumulator, current, _state, completed_count}, on_game) do
    on_game.(
      finish_game(current),
      completed_count + 1,
      accumulator
    )
  end

  defp normalize_line(line) do
    line
    |> String.trim_trailing("\n")
    |> String.trim_trailing("\r")
  end

  defp finish_game(lines) do
    lines
    |> Enum.reverse()
    |> Enum.join("\n")
    |> String.trim()
  end

  defp header_line?(line) do
    Regex.match?(
      @header_line_regex,
      line
    )
  end

  defp parse_game(game, index, parsed_games) do
    case PgnImporter.parse(game) do
      {:ok, parsed} ->
        {:ok,
         [
           parsed
           | parsed_games
         ]}

      {:error,
       {
         :invalid_pgn,
         _message
       } = reason} ->
        {:error,
         {
           :invalid_game,
           index,
           reason
         }}
    end
  end

  defp import_stream_game(game, index, imported_count, record_id_for_index) do
    case PgnImporter.parse(game) do
      {:ok, parsed} ->
        import_stream_parsed_game(
          parsed,
          index,
          imported_count,
          record_id_for_index
        )

      {:error,
       {
         :invalid_pgn,
         _message
       } = reason} ->
        {:error,
         {
           :invalid_game,
           index,
           reason
         }}
    end
  end

  defp import_stream_parsed_game(parsed, index, imported_count, record_id_for_index) do
    record_id =
      record_id_for_index.(index)

    if is_binary(record_id) and
         byte_size(record_id) > 0 do
      case PgnImporter.import_parsed(
             record_id,
             parsed
           ) do
        {:ok, _record} ->
          {:ok, imported_count + 1}

        {:error, reason} ->
          {:error,
           {
             :import_failed,
             index,
             reason
           }}
      end
    else
      {:error,
       {
         :invalid_record_id,
         index
       }}
    end
  end

  defp queue_parallel_game(game, index, state, record_id_for_index, max_concurrency, window_size) do
    state = %{
      state
      | pending: [
          {
            index,
            game
          }
          | state.pending
        ]
    }

    if length(state.pending) >= window_size do
      flush_parallel_games(
        state,
        record_id_for_index,
        max_concurrency
      )
    else
      {:ok, state}
    end
  end

  defp flush_parallel_games(%{pending: []} = state, _record_id_for_index, _max_concurrency) do
    {:ok, state}
  end

  defp flush_parallel_games(state, record_id_for_index, max_concurrency) do
    pending =
      Enum.reverse(state.pending)

    state = %{
      state
      | pending: []
    }

    pending
    |> Task.async_stream(
      fn {index, game} ->
        {
          index,
          import_parallel_game(
            game,
            index,
            record_id_for_index
          )
        }
      end,
      max_concurrency: max_concurrency,
      ordered: false,
      timeout: :infinity
    )
    |> Enum.reduce_while(
      {:ok, state},
      fn
        {
          :ok,
          {
            _index,
            :ok
          }
        },
        {
          :ok,
          state
        } ->
          {:cont,
           {
             :ok,
             %{
               state
               | imported_count: state.imported_count + 1
             }
           }}

        {
          :ok,
          {
            _index,
            {
              :error,
              failure
            }
          }
        },
        {
          :ok,
          state
        } ->
          {:cont,
           {
             :ok,
             %{
               state
               | failures: [
                   failure
                   | state.failures
                 ]
             }
           }}

        {
          :exit,
          reason
        },
        {
          :ok,
          _state
        } ->
          {:halt,
           {
             :error,
             {
               :parallel_worker_exit,
               reason
             }
           }}
      end
    )
  end

  defp import_parallel_game(game, index, record_id_for_index) do
    case PgnImporter.parse(game) do
      {:ok, parsed} ->
        import_parallel_parsed_game(
          parsed,
          index,
          record_id_for_index
        )

      {:error,
       {
         :invalid_pgn,
         _message
       } = reason} ->
        {:error,
         {
           :invalid_game,
           index,
           reason
         }}
    end
  end

  defp import_parallel_parsed_game(parsed, index, record_id_for_index) do
    record_id =
      record_id_for_index.(index)

    if is_binary(record_id) and
         byte_size(record_id) > 0 do
      case PgnImporter.import_parsed(
             record_id,
             parsed
           ) do
        {:ok, _record} ->
          :ok

        {:error, reason} ->
          {:error,
           {
             :import_failed,
             index,
             reason
           }}
      end
    else
      {:error,
       {
         :invalid_record_id,
         index
       }}
    end
  end

  defp parallel_failure_index({:invalid_game, index, _reason}) do
    index
  end

  defp parallel_failure_index({:invalid_record_id, index}) do
    index
  end

  defp parallel_failure_index({:import_failed, index, _reason}) do
    index
  end

  defp validate_max_concurrency(max_concurrency)
       when is_integer(max_concurrency) and max_concurrency > 0 do
    :ok
  end

  defp validate_max_concurrency(max_concurrency) do
    {:error,
     {
       :invalid_max_concurrency,
       max_concurrency
     }}
  end

  defp validate_window_size(window_size, max_concurrency)
       when is_integer(window_size) and window_size >= max_concurrency do
    :ok
  end

  defp validate_window_size(window_size, _max_concurrency) do
    {:error, {:invalid_window_size, window_size}}
  end

  defp validate_record_ids(record_ids) do
    record_ids
    |> Enum.with_index(1)
    |> Enum.reduce_while(
      {
        :ok,
        MapSet.new()
      },
      fn
        {
          record_id,
          index
        },
        {
          :ok,
          seen
        } ->
          cond do
            not is_binary(record_id) or
                byte_size(record_id) == 0 ->
              {:halt,
               {
                 :error,
                 {
                   :invalid_record_id,
                   index
                 }
               }}

            MapSet.member?(
              seen,
              record_id
            ) ->
              {:halt,
               {
                 :error,
                 {
                   :duplicate_record_id,
                   index
                 }
               }}

            true ->
              {:cont,
               {
                 :ok,
                 MapSet.put(
                   seen,
                   record_id
                 )
               }}
          end
      end
    )
    |> case do
      {:ok, _seen} ->
        :ok

      {:error, _reason} = error ->
        error
    end
  end

  defp validate_record_id_count(record_ids, parsed_games) do
    game_count =
      length(parsed_games)

    record_id_count =
      length(record_ids)

    if game_count ==
         record_id_count do
      :ok
    else
      {:error,
       {
         :record_id_count_mismatch,
         game_count,
         record_id_count
       }}
    end
  end

  defp persist_games(record_ids, parsed_games) do
    record_ids
    |> Enum.zip(parsed_games)
    |> Enum.with_index(1)
    |> Enum.reduce_while(
      {
        :ok,
        []
      },
      fn
        {
          {
            record_id,
            parsed
          },
          index
        },
        {
          :ok,
          records
        } ->
          case PgnImporter.import_parsed(
                 record_id,
                 parsed
               ) do
            {:ok, record} ->
              {:cont,
               {
                 :ok,
                 [
                   record
                   | records
                 ]
               }}

            {:error, reason} ->
              {:halt,
               {
                 :error,
                 {
                   :import_failed,
                   index,
                   reason
                 }
               }}
          end
      end
    )
    |> case do
      {:ok, records} ->
        {:ok, Enum.reverse(records)}

      {:error, _reason} = error ->
        error
    end
  end
end
