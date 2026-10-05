defmodule Analysis.PgnBatchImporter do
  @moduledoc """
  Parses headered multi-game PGN input through the single-game importer.

  The batch boundary identifies individual games and delegates the chess
  semantics of each game to `Analysis.PgnImporter`.

  Parsing a batch does not create durable game records. Concrete record
  identity and persistence policy belong to the caller of the later
  durable batch-import operation.

  Each game in a batch must start with a PGN tag-pair section. Tagless
  single games remain supported directly by `Analysis.PgnImporter`.
  """

  alias Analysis.PgnImporter

  @header_line_regex ~r/^\s*\[[A-Za-z0-9_]+\s+"(?:\\.|[^"])*"\]\s*$/

  @type parse_error ::
          :empty_batch
          | :game_headers_required
          | {:invalid_game, pos_integer(), {:invalid_pgn, String.t()}}

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
end
