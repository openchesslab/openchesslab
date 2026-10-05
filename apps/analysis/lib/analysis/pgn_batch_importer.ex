defmodule Analysis.PgnBatchImporter do
  @moduledoc """
  Parses and imports headered multi-game PGN input through the single-game importer.

  The batch boundary identifies individual games and delegates the chess
  semantics of each game to `Analysis.PgnImporter`.

  Durable batch import requires one caller-owned game-record ID per game.
  The complete batch is parsed before persistence starts, so parse errors
  never create partial durable imports.

  Persistence is intentionally atomic per game rather than per batch.
  If persistence of a later game fails, games imported before that game
  remain durable and the failing one-based game index is returned.

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

  @spec parse(String.t()) ::
          {:ok, [PgnImporter.result()]}
          | {:error, parse_error()}
  def parse(pgn) when is_binary(pgn) do
    with {:ok, games} <-
           split_games(pgn) do
      parse_games(games)
    end
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
         {:ok, games} <-
           split_games(pgn),
         {:ok, parsed_games} <-
           parse_games(games),
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

  defp split_games(pgn) do
    pgn
    |> String.split(
      ~r/\R/,
      trim: false
    )
    |> Enum.reduce_while(
      {
        :ok,
        [],
        [],
        :before_game
      },
      &split_line/2
    )
    |> finish_split()
  end

  defp split_line(line, {:ok, games, current, state}) do
    cond do
      String.trim(line) == "" ->
        split_blank_line(
          line,
          games,
          current,
          state
        )

      header_line?(line) ->
        split_header_line(
          line,
          games,
          current,
          state
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
           games,
           [line | current],
           :movetext
         }}
    end
  end

  defp split_blank_line(_line, games, [], :before_game) do
    {:cont,
     {
       :ok,
       games,
       [],
       :before_game
     }}
  end

  defp split_blank_line(line, games, current, state) do
    {:cont,
     {
       :ok,
       games,
       [line | current],
       state
     }}
  end

  defp split_header_line(line, games, current, :movetext) do
    game =
      finish_game(current)

    {:cont,
     {
       :ok,
       [game | games],
       [line],
       :headers
     }}
  end

  defp split_header_line(line, games, current, _state) do
    {:cont,
     {
       :ok,
       games,
       [line | current],
       :headers
     }}
  end

  defp finish_split({:error, reason}) do
    {:error, reason}
  end

  defp finish_split({:ok, [], [], :before_game}) do
    {:error, :empty_batch}
  end

  defp finish_split({:ok, games, current, _state}) do
    games =
      [finish_game(current) | games]
      |> Enum.reverse()

    {:ok, games}
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

  defp parse_games(games) do
    games
    |> Enum.with_index(1)
    |> Enum.reduce_while(
      {:ok, []},
      fn {game, index}, {:ok, parsed_games} ->
        case PgnImporter.parse(game) do
          {:ok, parsed} ->
            {:cont,
             {
               :ok,
               [parsed | parsed_games]
             }}

          {:error,
           {
             :invalid_pgn,
             _message
           } = reason} ->
            {:halt,
             {
               :error,
               {
                 :invalid_game,
                 index,
                 reason
               }
             }}
        end
      end
    )
    |> case do
      {:ok, parsed_games} ->
        {:ok, Enum.reverse(parsed_games)}

      {:error, _reason} = error ->
        error
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
