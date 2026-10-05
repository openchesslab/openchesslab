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

  Persistence is intentionally atomic per game rather than per batch.

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
           [line | current],
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
       [line | current],
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
           [line],
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
       [line | current],
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
        {:ok, [parsed | parsed_games]}

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

  defp validate_record_ids(record_ids) do
    record_ids
    |> Enum.with_index(1)
    |> Enum.reduce_while(
      {:ok, MapSet.new()},
      fn {record_id, index}, {:ok, seen} ->
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

    if game_count == record_id_count do
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
      {:ok, []},
      fn {{record_id, parsed}, index}, {:ok, records} ->
        case PgnImporter.import_parsed(
               record_id,
               parsed
             ) do
          {:ok, record} ->
            {:cont,
             {
               :ok,
               [record | records]
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
