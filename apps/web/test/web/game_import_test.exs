defmodule Web.GameImportTest do
  use ExUnit.Case, async: false

  alias Web.GameImport

  setup do
    original = Application.fetch_env(:web, :game_import_request)

    on_exit(fn ->
      case original do
        {:ok, value} -> Application.put_env(:web, :game_import_request, value)
        :error -> Application.delete_env(:web, :game_import_request)
      end
    end)
  end

  describe "split_input/1" do
    test "separates Lichess and Chess.com URLs from PGN text" do
      text = """
      [Event "A"]

      1. e4 e5 1-0
      https://lichess.org/LhL9TRJY
      https://lichess.org/PndlSDZg/black
      https://www.chess.com/game/live/123
      """

      assert %{
               lichess_ids: ["LhL9TRJY", "PndlSDZg"],
               chesscom_urls: ["https://www.chess.com/game/live/123"],
               pgn: pgn
             } = GameImport.split_input(text)

      assert pgn =~ "1. e4 e5"
      refute pgn =~ "lichess"
    end

    test "pure PGN input has no URLs and vice versa" do
      assert %{lichess_ids: [], chesscom_urls: [], pgn: "1. d4 d5 *"} =
               GameImport.split_input("1. d4 d5 *")

      assert %{lichess_ids: ["LhL9TRJY"], pgn: nil} =
               GameImport.split_input("https://lichess.org/LhL9TRJY")
    end
  end

  describe "fetch_lichess_user_games/2" do
    test "returns the PGN body on success" do
      stub([{200, "[Event \"x\"]\n\n1. e4 e5 1-0\n"}])

      assert {:ok, pgn} = GameImport.fetch_lichess_user_games("someone", 5)
      assert pgn =~ "1. e4 e5"
    end

    test "maps provider failures to honest reasons" do
      stub([{404, ""}])
      assert {:error, :not_found} = GameImport.fetch_lichess_user_games("nobody", 5)

      stub([{429, ""}])
      assert {:error, :rate_limited} = GameImport.fetch_lichess_user_games("nobody", 5)

      stub([:timeout])
      assert {:error, :unreachable} = GameImport.fetch_lichess_user_games("nobody", 5)
    end
  end

  describe "fetch_lichess_games_by_ids/1" do
    test "returns the PGN and the ids that came back" do
      body = """
      [Event "a"]
      [Site "https://lichess.org/LhL9TRJY"]

      1. e4 e5 1-0
      """

      stub([{200, body}])

      assert {:ok, ^body, ["LhL9TRJY"]} =
               GameImport.fetch_lichess_games_by_ids(["LhL9TRJY", "ZZZZZZZZ"])
    end
  end

  describe "fetch_chesscom_user_games/2" do
    test "takes the newest games from the latest monthly archive" do
      archives = %{"archives" => ["https://api.chess.com/pub/player/x/games/2026/09"]}

      month = %{
        "games" => [
          %{"end_time" => 200, "pgn" => "[Event \"new\"]\n\n1. d4 d5 *"},
          %{"end_time" => 100, "pgn" => "[Event \"old\"]\n\n1. e4 e5 *"}
        ]
      }

      stub([{200, Jason.encode!(archives)}, {200, Jason.encode!(month)}])

      assert {:ok, pgn} = GameImport.fetch_chesscom_user_games("x", 1)
      assert pgn =~ "new"
      refute pgn =~ "old"
    end

    test "unknown user and empty archive are honest errors" do
      stub([{404, ""}])
      assert {:error, :not_found} = GameImport.fetch_chesscom_user_games("nobody", 5)

      stub([{200, Jason.encode!(%{"archives" => []})}])
      assert {:error, :no_games} = GameImport.fetch_chesscom_user_games("quiet", 5)
    end
  end

  defp stub(responses) do
    agent =
      start_supervised!(%{id: make_ref(), start: {Agent, :start_link, [fn -> responses end]}})

    request = fn _method, _payload, _http, _options ->
      Agent.get_and_update(agent, fn
        [:timeout | rest] -> {{:error, :timeout}, rest}
        [{status, body} | rest] -> {{:ok, {{~c"HTTP/1.1", status, ~c""}, [], body}}, rest}
      end)
    end

    Application.put_env(:web, :game_import_request, request)
  end
end
