defmodule Web.PgnImporter do
  @moduledoc """
  Small main-line PGN reader used by the web demo importer.

  This is deliberately scoped to the UI's pasted/sample PGNs: it reads
  SAN from the standard starting position, ignores comments and side
  variations, and asks the chess application to validate every move.
  It is not a replacement for a canonical game import service.
  """

  alias Chess.Notation.SAN
  alias Chess.Position

  @max_pgn_bytes 100_000

  @type result :: %{
          headers: %{optional(String.t()) => String.t()},
          moves: [Chess.Move.t()],
          final_position: Position.t()
        }

  @spec parse(String.t()) :: {:ok, result()} | {:error, {:invalid_pgn, String.t()}}
  def parse(pgn) when is_binary(pgn) and byte_size(pgn) <= @max_pgn_bytes do
    headers = parse_headers(pgn)

    pgn
    |> movetext()
    |> tokenize()
    |> replay(Position.starting_position(), [])
    |> case do
      {:ok, position, moves} ->
        if moves == [] do
          {:error, {:invalid_pgn, "No moves found"}}
        else
          {:ok, %{headers: headers, moves: Enum.reverse(moves), final_position: position}}
        end

      {:error, message} ->
        {:error, {:invalid_pgn, message}}
    end
  end

  def parse(_pgn), do: {:error, {:invalid_pgn, "PGN is too large or invalid"}}

  defp parse_headers(pgn) do
    Regex.scan(~r/^\s*\[([A-Za-z0-9_]+)\s+"((?:\\.|[^"])*)"\]\s*$/m, pgn)
    |> Map.new(fn [_, key, value] ->
      value = value |> String.replace("\\\"", "\"") |> String.replace("\\\\", "\\")
      {key, value}
    end)
  end

  defp movetext(pgn) do
    pgn
    |> String.replace(~r/^\s*\[[^\]]+\]\s*$/m, " ")
    |> String.replace(~r/\{[^}]*\}/s, " ")
    |> String.replace(~r/;[^\r\n]*/, " ")
    |> String.replace(~r/\$\d+/, " ")
    |> strip_variations(0)
  end

  defp strip_variations(text, 20), do: text

  defp strip_variations(text, depth) do
    stripped = String.replace(text, ~r/\([^()]*\)/, " ")
    if stripped == text, do: text, else: strip_variations(stripped, depth + 1)
  end

  defp tokenize(text) do
    text
    |> String.split(~r/\s+/, trim: true)
    |> Enum.flat_map(&split_move_number/1)
    |> Enum.reject(&result_token?/1)
  end

  defp split_move_number(token) do
    case Regex.run(~r/^\d+\.(?:\.\.)?(.*)$/, token) do
      [_, ""] -> []
      [_, move] -> [move]
      _ -> [token]
    end
  end

  defp result_token?(token), do: token in ["1-0", "0-1", "1/2-1/2", "*"]

  defp replay([], position, moves), do: {:ok, position, moves}

  defp replay([token | rest], position, moves) do
    token = normalize_san(token)

    case matching_move(position, token) do
      nil ->
        {:error, "Could not parse move #{token}"}

      move ->
        case Position.apply_move(position, move) do
          {:ok, next_position} -> replay(rest, next_position, [move | moves])
          {:error, :illegal_move} -> {:error, "Illegal move #{token}"}
        end
    end
  end

  defp matching_move(position, token) do
    Enum.find(Position.legal_moves(position), fn move ->
      case SAN.format(position, move) do
        {:ok, san} -> normalize_san(san) == token
        _ -> false
      end
    end)
  end

  defp normalize_san(token) do
    token
    |> String.replace("0-0-0", "O-O-O")
    |> String.replace("0-0", "O-O")
    |> String.replace(~r/e\.p\.?$/i, "")
    |> String.replace(~r/[!?]+$/, "")
  end
end
