defmodule Web.GameImport do
  @moduledoc """
  Fetches games from the public Lichess and Chess.com APIs as PGN text, and
  classifies the import box's mixed input: game URLs are fetched, the rest is
  PGN. Both providers throttle and require a descriptive User-Agent; Chess.com
  game URLs cannot be resolved publicly, so only Lichess URLs are recognized.

  The request function is a test seam: `Application.get_env(:web,
  :game_import_request)` overrides the default `:httpc.request/4`.
  """

  @user_agent ~c"OpenChessLab/1.0 (+https://openchesslab.com)"
  @timeout_ms 15_000

  @lichess_game_url ~r/^https?:\/\/(?:www\.)?lichess\.org\/(?<id>[A-Za-z0-9]{8})(?:[\/#?].*)?$/
  @chesscom_url ~r/^https?:\/\/(?:www\.)?chess\.com\//

  @type split :: %{
          lichess_ids: [String.t()],
          chesscom_urls: [String.t()],
          pgn: String.t() | nil
        }

  @type fetch_error :: :not_found | :no_games | :rate_limited | :unreachable

  @typedoc """
  A selection row for the import tray: who played, how it ended, the speed
  and the year. Chess.com rows also carry the full `pgn` (the monthly
  archive is the only public listing, so it arrives whole).
  """
  @type game_row :: %{
          optional(:pgn) => String.t(),
          id: String.t(),
          white: String.t(),
          black: String.t(),
          result: String.t(),
          speed: String.t(),
          year: integer() | String.t()
        }

  @doc """
  Classifies the import box line by line: a trimmed line that is a Lichess
  game URL contributes its game id, a Chess.com URL is reported separately
  (it cannot be fetched), and everything else stays PGN text.
  """
  @spec split_input(String.t()) :: split()
  def split_input(text) when is_binary(text) do
    Enum.reduce(
      String.split(text, ~r/\R/),
      %{lichess_ids: [], chesscom_urls: [], pgn: []},
      fn line, acc ->
        trimmed = String.trim(line)

        case lichess_game_id(trimmed) do
          nil ->
            if Regex.match?(@chesscom_url, trimmed),
              do: %{acc | chesscom_urls: [trimmed | acc.chesscom_urls]},
              else: %{acc | pgn: [line | acc.pgn]}

          id ->
            %{acc | lichess_ids: [id | acc.lichess_ids]}
        end
      end
    )
    |> then(fn acc ->
      pgn = acc.pgn |> Enum.reverse() |> Enum.join("\n") |> String.trim()

      %{
        lichess_ids: Enum.reverse(acc.lichess_ids),
        chesscom_urls: Enum.reverse(acc.chesscom_urls),
        pgn: if(pgn == "", do: nil, else: pgn)
      }
    end)
  end

  defp lichess_game_id(line) do
    case Regex.named_captures(@lichess_game_url, line) do
      %{"id" => id} -> id
      nil -> nil
    end
  end

  @doc """
  Fetches the given Lichess game ids in one batch export. Returns the PGN and
  the ids that actually came back, so the caller can report the missing ones.
  """
  @spec fetch_lichess_games_by_ids([String.t()]) ::
          {:ok, String.t(), [String.t()]} | {:error, fetch_error()}
  def fetch_lichess_games_by_ids(ids) when is_list(ids) and ids != [] do
    body = Enum.join(ids, ",")

    case request().(
           :post,
           {~c"https://lichess.org/api/games/export/_ids", headers("application/x-chess-pgn"),
            ~c"text/plain", String.to_charlist(body)},
           http_options(),
           []
         ) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        pgn = to_string(body)
        {:ok, pgn, lichess_ids_in(pgn)}

      {:ok, {{_, 429, _}, _, _}} ->
        {:error, :rate_limited}

      {:ok, {{_, status, _}, _, _}} when status in [400, 404] ->
        {:error, :not_found}

      _ ->
        {:error, :unreachable}
    end
  end

  @doc """
  The username of the account a Lichess grant belongs to. `{:error,
  :unauthorized}` means the grant was revoked or expired — delete it.
  """
  @spec fetch_lichess_account_username(String.t()) ::
          {:ok, String.t()} | {:error, fetch_error() | :unauthorized}
  def fetch_lichess_account_username(token) when is_binary(token) do
    case request().(
           :get,
           {~c"https://lichess.org/api/account", headers("application/json", token)},
           http_options(),
           []
         ) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        case Jason.decode(to_string(body)) do
          {:ok, %{"username" => username}} when is_binary(username) -> {:ok, username}
          _ -> {:error, :unreachable}
        end

      {:ok, {{_, 401, _}, _, _}} ->
        {:error, :unauthorized}

      {:ok, {{_, 429, _}, _, _}} ->
        {:error, :rate_limited}

      _ ->
        {:error, :unreachable}
    end
  end

  @doc """
  Games newer than `since` (a `lastMoveAt` cursor in milliseconds, nil for the
  beginning) for a Lichess account, oldest first — the sync shape: id, PGN,
  display title and cursor value per game.
  """
  @spec fetch_lichess_games_since(String.t(), integer() | nil, pos_integer()) ::
          {:ok, [%{id: String.t(), pgn: String.t(), title: String.t(), last_move_at: integer()}]}
          | {:error, fetch_error() | :unauthorized}
  def fetch_lichess_games_since(username, since, max) do
    url =
      "https://lichess.org/api/games/user/#{URI.encode(username)}?max=#{max}&sort=dateAsc&pgnInJson=true" <>
        if(since, do: "&since=#{since}", else: "")

    case request().(
           :get,
           {String.to_charlist(url), headers("application/x-ndjson")},
           http_options(),
           []
         ) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        {:ok, parse_game_lines(to_string(body))}

      {:ok, {{_, 401, _}, _, _}} ->
        {:error, :unauthorized}

      {:ok, {{_, 404, _}, _, _}} ->
        {:error, :not_found}

      {:ok, {{_, 429, _}, _, _}} ->
        {:error, :rate_limited}

      _ ->
        {:error, :unreachable}
    end
  end

  defp parse_game_lines(body) do
    body
    |> String.split("\n", trim: true)
    |> Enum.filter(&String.contains?(&1, ~s("pgn")))
    |> Enum.map(&Jason.decode!/1)
    |> Enum.map(fn game ->
      %{
        id: game["id"],
        pgn: game["pgn"],
        title: game_title(game),
        last_move_at: game["lastMoveAt"] || game["createdAt"]
      }
    end)
  end

  @doc """
  The most recent public games of a Lichess account as metadata rows,
  newest first — the selection list for the import tray. The rows carry
  no moves; `fetch_lichess_games_by_ids/1` fetches the chosen PGNs.
  """
  @spec fetch_lichess_recent_games(String.t(), pos_integer()) ::
          {:ok, [game_row()]} | {:error, fetch_error()}
  def fetch_lichess_recent_games(username, max) do
    url = "https://lichess.org/api/games/user/#{URI.encode(username)}?max=#{max}"

    case request().(
           :get,
           {String.to_charlist(url), headers("application/x-ndjson")},
           http_options(),
           []
         ) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        rows =
          body
          |> to_string()
          |> String.split("\n", trim: true)
          |> Enum.map(fn line -> recent_row(Jason.decode!(line)) end)

        {:ok, rows}

      {:ok, {{_, 404, _}, _, _}} ->
        {:error, :not_found}

      {:ok, {{_, 429, _}, _, _}} ->
        {:error, :rate_limited}

      _ ->
        {:error, :unreachable}
    end
  end

  defp recent_row(game) do
    %{
      id: game["id"],
      white: player_name(game, "white"),
      black: player_name(game, "black"),
      result: game_result(game),
      speed: game["speed"] || "?",
      year: game_year(game)
    }
  end

  defp game_title(game) do
    row = recent_row(game)
    "#{row.white} – #{row.black} #{row.result} (#{row.year})"
  end

  defp game_result(game) do
    case game["winner"] do
      "white" -> "1-0"
      "black" -> "0-1"
      _ -> "½-½"
    end
  end

  defp game_year(game) do
    case game["lastMoveAt"] || game["createdAt"] do
      ms when is_integer(ms) -> DateTime.from_unix!(ms, :millisecond).year
      _ -> "?"
    end
  end

  defp player_name(game, color),
    do: get_in(game, ["players", color, "user", "name"]) || "Anonymous"

  @doc """
  One month of public Chess.com games as rows, newest first. Each row
  carries its full PGN and uses the game URL as id — the monthly archive
  is the only public listing, so the import tray selects from these rows
  without refetching.
  """
  @spec fetch_chesscom_month_games(String.t(), pos_integer(), pos_integer()) ::
          {:ok, [game_row()]} | {:error, fetch_error()}
  def fetch_chesscom_month_games(username, year, month)
      when year > 0 and month in 1..12 do
    padded = String.pad_leading(Integer.to_string(month), 2, "0")

    url =
      "https://api.chess.com/pub/player/#{URI.encode(String.downcase(username))}/games/#{year}/#{padded}"

    case get_json(url) do
      {:ok, %{"games" => [_ | _] = games}} ->
        rows =
          games
          |> Enum.sort_by(&(&1["end_time"] || 0), :desc)
          |> Enum.map(&chesscom_row/1)

        {:ok, rows}

      {:ok, _} ->
        {:error, :no_games}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  The monthly archives a Chess.com user has, newest first, as `{year, month}`
  tuples — the friendly alternative to typing a month by hand.
  """
  @spec fetch_chesscom_archives(String.t()) ::
          {:ok, [{pos_integer(), 1..12}]} | {:error, fetch_error()}
  def fetch_chesscom_archives(username) when is_binary(username) do
    url =
      "https://api.chess.com/pub/player/#{URI.encode(String.downcase(username))}/games/archives"

    case get_json(url) do
      {:ok, %{"archives" => archives}} when is_list(archives) ->
        months =
          archives
          |> Enum.flat_map(fn archive ->
            case Regex.run(~r"/games/(\d{4})/(\d{2})$", archive) do
              [_, year, month] -> [{String.to_integer(year), String.to_integer(month)}]
              _ -> []
            end
          end)
          |> Enum.uniq()
          |> Enum.sort(:desc)

        {:ok, months}

      {:ok, _other} ->
        {:error, :no_games}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp chesscom_row(game) do
    %{
      id: game["url"],
      white: get_in(game, ["white", "username"]) || "?",
      black: get_in(game, ["black", "username"]) || "?",
      result: chesscom_result(game),
      speed: game["time_class"] || "?",
      year: chesscom_year(game),
      pgn: game["pgn"] || ""
    }
  end

  defp chesscom_result(game) do
    cond do
      get_in(game, ["white", "result"]) == "win" -> "1-0"
      get_in(game, ["black", "result"]) == "win" -> "0-1"
      true -> "½-½"
    end
  end

  defp chesscom_year(game) do
    case game["end_time"] do
      seconds when is_integer(seconds) -> DateTime.from_unix!(seconds).year
      _ -> "?"
    end
  end

  defp get_json(url) do
    case request().(
           :get,
           {String.to_charlist(to_string(url)), headers("application/json")},
           http_options(),
           []
         ) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        case Jason.decode(to_string(body)) do
          {:ok, decoded} -> {:ok, decoded}
          _ -> {:error, :unreachable}
        end

      {:ok, {{_, 404, _}, _, _}} ->
        {:error, :not_found}

      {:ok, {{_, 429, _}, _, _}} ->
        {:error, :rate_limited}

      _ ->
        {:error, :unreachable}
    end
  end

  defp headers(accept), do: [{~c"user-agent", @user_agent}, {~c"accept", accept}]

  defp headers(accept, token),
    do: [{~c"authorization", String.to_charlist("Bearer " <> token)} | headers(accept)]

  defp http_options,
    do: [timeout: @timeout_ms, ssl: :httpc.ssl_verify_host_options(true)]

  defp request, do: Application.get_env(:web, :game_import_request, &:httpc.request/4)

  defp lichess_ids_in(pgn) do
    Regex.scan(~r/\[Site "https:\/\/lichess\.org\/([A-Za-z0-9]{8})"\]/, pgn)
    |> Enum.map(fn [_, id] -> id end)
  end
end
