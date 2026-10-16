defmodule Web.Tablebase do
  @moduledoc """
  Fetches exact endgame results from the public lichess tablebase API.

  Covers all standard positions with up to seven pieces. Positions with
  castling rights are not covered by the tablebase itself; callers skip them
  before asking. Every result is cached durably by
  `Analysis.PositionTablebases`, so the external service is asked once per
  unique position.

  The request function is a test seam: `Application.get_env(:web,
  :tablebase_request)` overrides the default `:httpc.request/4`.
  """

  @base_url "https://tablebase.lichess.ovh/standard"
  @user_agent ~c"OpenChessLab/1.0 (+https://openchesslab.com)"
  @timeout_ms 15_000

  @type move :: %{required(String.t()) => String.t() | integer() | nil}

  @type result :: %{
          required(String.t()) => String.t() | integer() | nil | [move()]
        }

  @doc """
  The tablebase result for a FEN. `category` and `dtz`/`dtm` are from the
  side to move's perspective; each move's category is from the perspective
  of the side that must move after it (the API's convention).
  """
  @spec fetch(String.t()) :: {:ok, result()} | {:error, :not_in_tablebase | :unreachable}
  def fetch(fen) when is_binary(fen) do
    query = fen |> String.replace(" ", "_") |> URI.encode()

    case request().(
           :get,
           {String.to_charlist(@base_url <> "?fen=" <> query), headers()},
           http_options(),
           []
         ) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        case Jason.decode(to_string(body)) do
          {:ok, decoded} -> {:ok, normalize(decoded)}
          _ -> {:error, :unreachable}
        end

      {:ok, {{_, 404, _}, _headers, _body}} ->
        {:error, :not_in_tablebase}

      _ ->
        {:error, :unreachable}
    end
  end

  defp normalize(decoded) do
    %{
      "category" => decoded["category"],
      "dtz" => decoded["dtz"],
      "dtm" => decoded["dtm"],
      "moves" =>
        for move <- decoded["moves"] || [] do
          %{
            "uci" => move["uci"],
            "san" => move["san"],
            "category" => move["category"],
            "dtz" => move["dtz"]
          }
        end
    }
  end

  defp headers, do: [{~c"user-agent", @user_agent}, {~c"accept", ~c"application/json"}]

  defp http_options, do: [timeout: @timeout_ms, ssl: :httpc.ssl_verify_host_options(true)]

  defp request, do: Application.get_env(:web, :tablebase_request, &:httpc.request/4)
end
