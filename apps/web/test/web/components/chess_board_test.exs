defmodule Web.Components.ChessBoardTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Chess.Position
  alias Web.Components.ChessBoard

  describe "chess_board/1" do
    test "renders all 64 squares" do
      html =
        render_component(&ChessBoard.chess_board/1,
          position: Position.starting_position()
        )

      assert html =~ ~s(id="chess-board")

      for square <- ~w(
            a1 b1 c1 d1 e1 f1 g1 h1
            a2 b2 c2 d2 e2 f2 g2 h2
            a3 b3 c3 d3 e3 f3 g3 h3
            a4 b4 c4 d4 e4 f4 g4 h4
            a5 b5 c5 d5 e5 f5 g5 h5
            a6 b6 c6 d6 e6 f6 g6 h6
            a7 b7 c7 d7 e7 f7 g7 h7
            a8 b8 c8 d8 e8 f8 g8 h8
          ) do
        assert html =~ ~s(id="square-#{square}")
      end
    end

    test "renders pieces on their squares" do
      html =
        render_component(&ChessBoard.chess_board/1,
          position: Position.starting_position()
        )

      assert html =~ ~r/id="piece-a1"[^>]*>\s*♖\s*</
      assert html =~ ~r/id="piece-e1"[^>]*>\s*♔\s*</
      assert html =~ ~r/id="piece-e2"[^>]*>\s*♙\s*</

      assert html =~ ~r/id="piece-a8"[^>]*>\s*♜\s*</
      assert html =~ ~r/id="piece-e8"[^>]*>\s*♚\s*</
      assert html =~ ~r/id="piece-e7"[^>]*>\s*♟\s*</
    end

    test "renders an empty square without a piece" do
      html =
        render_component(&ChessBoard.chess_board/1,
          position: Position.starting_position()
        )

      assert html =~ ~s(id="square-e4")
      refute html =~ ~s(id="piece-e4")
    end
  end

  test "renders squares as clickable board interactions" do
    html =
      render_component(&ChessBoard.chess_board/1,
        position: Position.starting_position()
      )

    assert html =~ ~s(id="square-e2")
    assert html =~ ~s(phx-click="square_clicked")
    assert html =~ ~s(phx-value-square="e2")
  end
end
