defmodule Analysis.PgnImporter do
  @moduledoc """
  Parses bounded single-game main-line PGNs and imports them as durable played games.

  PGNs are interpreted from the standard starting position. Comments,
  NAGs and side variations do not contribute to canonical played-game
  content and are ignored.

  Each parse or import operation accepts exactly one game. Multi-game
  PGN input is rejected explicitly and can later be handled by a
  dedicated bulk-import boundary.

  Custom FEN starting positions are not supported yet and are rejected
  explicitly rather than being interpreted as standard-start games.

  Durable imports are stored through `Analysis.GameRecords`, which owns
  canonical game reuse, occurrence creation and concrete game-record
  persistence.
  """

  alias Analysis.GameContent
  alias Analysis.GameRecord
  alias Analysis.GameRecords
  alias Analysis.GameStart
  alias Analysis.PositionStore
  alias Chess.Notation.SAN
  alias Chess.Position

  @max_pgn_bytes 100_000

  @header_line_regex ~r/^\s*\[([A-Za-z0-9_]+)\s+"((?:\\.|[^"])*)"\]\s*$/

  @type result :: %{
          headers: %{optional(String.t()) => String.t()},
          moves: [Chess.Move.t()],
          final_position: Position.t()
        }

  @type import_error ::
          {:invalid_pgn, String.t()}
          | GameRecords.create_error()

  @spec import_game(
          GameRecord.id(),
          String.t()
        ) ::
          {:ok, GameRecord.t()}
          | {:error, import_error()}
  def import_game(record_id, pgn) when is_binary(record_id) and byte_size(record_id) > 0 do
    with {:ok, parsed} <-
           parse(pgn),
         {:ok, initial_position_id} <-
           store_initial_position() do
      content =
        GameContent.new(
          initial_position_id,
          parsed.moves
        )

      GameRecords.create(
        record_id,
        content,
        GameStart.standard(),
        metadata(parsed.headers)
      )
    end
  end

  def import_game(_record_id, _pgn) do
    {:error, :invalid_record_id}
  end

  @spec parse(String.t()) ::
          {:ok, result()}
          | {:error, {:invalid_pgn, String.t()}}
  def parse(pgn) when is_binary(pgn) and byte_size(pgn) <= @max_pgn_bytes do
    headers =
      parse_headers(pgn)

    with :ok <-
           validate_single_game(pgn),
         :ok <-
           validate_standard_start(headers),
         {:ok, position, moves} <-
           pgn
           |> movetext()
           |> tokenize()
           |> replay(
             Position.starting_position(),
             []
           ) do
      if moves == [] do
        {:error, {:invalid_pgn, "No moves found"}}
      else
        {:ok,
         %{
           headers: headers,
           moves: Enum.reverse(moves),
           final_position: position
         }}
      end
    else
      {:error, message} ->
        {:error, {:invalid_pgn, message}}
    end
  end

  def parse(_pgn) do
    {:error, {:invalid_pgn, "PGN is too large or invalid"}}
  end

  defp store_initial_position do
    case PositionStore.append(Position.starting_position()) do
      position_id
      when is_integer(position_id) and
             position_id > 0 ->
        {:ok, position_id}

      {:error, reason} ->
        {:error,
         {
           :position_store,
           reason
         }}
    end
  end

  defp metadata(headers) do
    Map.new(
      headers,
      fn {key, value} ->
        {
          Macro.underscore(key),
          value
        }
      end
    )
  end

  defp validate_single_game(pgn) do
    cleaned =
      strip_non_mainline_noise(pgn)

    tokens =
      cleaned
      |> remove_headers()
      |> String.split(
        ~r/\s+/,
        trim: true
      )

    if header_after_movetext?(cleaned) or
         content_after_result?(tokens) or
         repeated_first_move_number?(tokens) do
      {:error, "Multiple games are not supported"}
    else
      :ok
    end
  end

  defp header_after_movetext?(pgn) do
    pgn
    |> String.split(~r/\R/)
    |> Enum.reduce_while(
      :before_movetext,
      fn line, state ->
        cond do
          String.trim(line) == "" ->
            {:cont, state}

          Regex.match?(
            @header_line_regex,
            line
          ) and state == :movetext ->
            {:halt, :multiple_games}

          Regex.match?(
            @header_line_regex,
            line
          ) ->
            {:cont, state}

          true ->
            {:cont, :movetext}
        end
      end
    )
    |> case do
      :multiple_games ->
        true

      _state ->
        false
    end
  end

  defp content_after_result?(tokens) do
    case Enum.split_while(
           tokens,
           &(not result_token?(&1))
         ) do
      {_before, []} ->
        false

      {_before, [_result]} ->
        false

      {_before, [_result | _after_result]} ->
        true
    end
  end

  defp repeated_first_move_number?(tokens) do
    Enum.count(
      tokens,
      &Regex.match?(
        ~r/^1\.(?!\.)/,
        &1
      )
    ) > 1
  end

  defp validate_standard_start(headers) do
    if headers["SetUp"] == "1" or
         Map.has_key?(
           headers,
           "FEN"
         ) do
      {:error, "Custom starting positions are not supported"}
    else
      :ok
    end
  end

  defp parse_headers(pgn) do
    Regex.scan(
      ~r/^\s*\[([A-Za-z0-9_]+)\s+"((?:\\.|[^"])*)"\]\s*$/m,
      pgn
    )
    |> Map.new(fn [
                    _match,
                    key,
                    value
                  ] ->
      value =
        value
        |> String.replace(
          "\\\"",
          "\""
        )
        |> String.replace(
          "\\\\",
          "\\"
        )

      {
        key,
        value
      }
    end)
  end

  defp movetext(pgn) do
    pgn
    |> remove_headers()
    |> strip_non_mainline_noise()
  end

  defp remove_headers(pgn) do
    String.replace(
      pgn,
      ~r/^\s*\[[^\]]+\]\s*$/m,
      " "
    )
  end

  defp strip_non_mainline_noise(pgn) do
    pgn
    |> String.replace(
      ~r/\{[^}]*\}/s,
      " "
    )
    |> String.replace(
      ~r/;[^\r\n]*/,
      " "
    )
    |> String.replace(
      ~r/\$\d+/,
      " "
    )
    |> strip_variations(0)
  end

  defp strip_variations(text, 20) do
    text
  end

  defp strip_variations(text, depth) do
    stripped =
      String.replace(
        text,
        ~r/\([^()]*\)/,
        " "
      )

    if stripped == text do
      text
    else
      strip_variations(
        stripped,
        depth + 1
      )
    end
  end

  defp tokenize(text) do
    text
    |> String.split(
      ~r/\s+/,
      trim: true
    )
    |> Enum.flat_map(&split_move_number/1)
    |> Enum.reject(&result_token?/1)
  end

  defp split_move_number(token) do
    case Regex.run(
           ~r/^\d+\.(?:\.\.)?(.*)$/,
           token
         ) do
      [
        _match,
        ""
      ] ->
        []

      [
        _match,
        move
      ] ->
        [move]

      _other ->
        [token]
    end
  end

  defp result_token?(token) do
    token in [
      "1-0",
      "0-1",
      "1/2-1/2",
      "*"
    ]
  end

  defp replay([], position, moves) do
    {:ok, position, moves}
  end

  defp replay([token | rest], position, moves) do
    token =
      normalize_san(token)

    case SAN.parse(
           position,
           token
         ) do
      {:ok, move} ->
        case Position.apply_move(
               position,
               move
             ) do
          {:ok, next_position} ->
            replay(
              rest,
              next_position,
              [move | moves]
            )

          {:error, :illegal_move} ->
            {:error, "Illegal move #{token}"}
        end

      {:error, :invalid_san} ->
        {:error, "Could not parse move #{token}"}
    end
  end

  defp normalize_san(token) do
    token
    |> String.replace(
      "0-0-0",
      "O-O-O"
    )
    |> String.replace(
      "0-0",
      "O-O"
    )
    |> String.replace(
      ~r/e\.p\.?$/i,
      ""
    )
    |> String.replace(
      ~r/[!?]+$/,
      ""
    )
  end
end
