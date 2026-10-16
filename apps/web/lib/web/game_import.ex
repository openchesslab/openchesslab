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

  @doc "The most recent public games of a Lichess account as PGN."
  @spec fetch_lichess_user_games(String.t(), pos_integer()) ::
          {:ok, String.t()} | {:error, fetch_error()}
  def fetch_lichess_user_games(username, max) do
    url =
      "https://lichess.org/api/games/user/#{URI.encode(username)}?max=#{max}&clocks=false&evals=false"

    case request().(
           :get,
           {String.to_charlist(url), headers("application/x-chess-pgn")},
           http_options(),
           []
         ) do
      {:ok, {{_, 200, _}, _headers, body}} -> {:ok, to_string(body)}
      {:ok, {{_, 404, _}, _, _}} -> {:error, :not_found}
      {:ok, {{_, 429, _}, _, _}} -> {:error, :rate_limited}
      _ -> {:error, :unreachable}
    end
  end

  @doc """
  The most recent public games of a Chess.com account as PGN, taken from the
  latest monthly archive (the public API exposes no single-game lookup).
  """
  @spec fetch_chesscom_user_games(String.t(), pos_integer()) ::
          {:ok, String.t()} | {:error, fetch_error()}
  def fetch_chesscom_user_games(username, max) do
    base = "https://api.chess.com/pub/player/#{URI.encode(String.downcase(username))}/games"

    with {:ok, archives} <- get_json("#{base}/archives"),
         {:ok, latest} <- latest_archive(archives),
         {:ok, %{"games" => games}} <- get_json(latest) do
      games
      |> Enum.sort_by(& &1["end_time"])
      |> Enum.take(-max)
      |> Enum.map(& &1["pgn"])
      |> case do
        [] -> {:error, :no_games}
        pgns -> {:ok, Enum.join(pgns, "\n\n")}
      end
    end
  end

  defp latest_archive(%{"archives" => [_ | _] = archives}), do: {:ok, List.last(archives)}
  defp latest_archive(_), do: {:error, :no_games}

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
