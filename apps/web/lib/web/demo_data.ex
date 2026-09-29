defmodule Web.DemoData do
  @moduledoc """
  Clearly labelled fixture data for backend features that do not exist yet.

  These fixtures are isolated to the web UI and are not persisted or
  represented as real engine/search results.
  """

  alias Chess.Notation.SAN
  alias Chess.Position

  @sample_pgn """
  [Event "OpenChessLab sample"]
  [Site "Local demo"]
  [Date "2026.01.01"]
  [White "Alice Example"]
  [Black "Boris Example"]
  [Result "*"]

  1. e4 {A classical opening} e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7 *
  """

  @fixtures [
    %{
      id: "demo-ruy-lopez",
      white: "Alice Example",
      black: "Boris Example",
      white_rating: 1820,
      black_rating: 1795,
      event: "OpenChessLab demo",
      date: "2026.01.01",
      result: "1/2-1/2",
      opening: "Ruy Lopez",
      ply_count: 10,
      pgn: @sample_pgn
    },
    %{
      id: "demo-queens-gambit",
      white: "Mira Sample",
      black: "Noah Example",
      white_rating: 1910,
      black_rating: 1870,
      event: "Demo collection",
      date: "2025.11.12",
      result: "1-0",
      opening: "Queen's Gambit",
      ply_count: 12,
      pgn: """
      [Event "OpenChessLab demo"]
      [White "Mira Sample"]
      [Black "Noah Example"]
      [Result "1-0"]

      1. d4 d5 2. c4 e6 3. Nc3 Nf6 4. Bg5 Be7 5. e3 O-O 6. Nf3 *
      """
    }
  ]

  @doc "Returns local fixture games filtered by the simple search form."
  def search_games(filters) when is_map(filters) do
    player = filters["player"] |> to_string() |> String.downcase() |> String.trim()
    opening = filters["opening"] |> to_string() |> String.downcase() |> String.trim()
    color = filters["color"] || "either"
    result = filters["result"] || "either"
    date_from = filters["date_from"] || ""
    date_to = filters["date_to"] || ""
    fen = filters["fen"] |> to_string() |> String.trim()

    Enum.filter(@fixtures, fn game ->
      player_match =
        case color do
          "white" ->
            player == "" or String.contains?(String.downcase(game.white), player)

          "black" ->
            player == "" or String.contains?(String.downcase(game.black), player)

          _ ->
            player == "" or
              String.contains?(String.downcase(game.white), player) or
              String.contains?(String.downcase(game.black), player)
        end

      opening_match = opening == "" or String.contains?(String.downcase(game.opening), opening)
      result_match = result == "either" or game.result == result

      date = String.replace(game.date, ".", "-")
      date_match = (date_from == "" or date >= date_from) and (date_to == "" or date <= date_to)

      position_match = fen == ""

      player_match and opening_match and result_match and date_match and position_match
    end)
  end

  @doc "Returns a fixture by id; callers still replay it through the chess rules."
  def game(id), do: Enum.find(@fixtures, &(&1.id == id))

  @doc "Creates illustrative, non-engine output for the demo panel."
  def engine_preview(%Position{} = position) do
    lines =
      position
      |> Position.legal_moves()
      |> Enum.take(3)
      |> Enum.map(fn move ->
        case SAN.format(position, move) do
          {:ok, san} -> san <> " …"
          _ -> "—"
        end
      end)

    %{
      eval_cp: 24,
      depth: 12,
      nodes: 18_240,
      nps: 61_000,
      pv: lines
    }
  end
end
