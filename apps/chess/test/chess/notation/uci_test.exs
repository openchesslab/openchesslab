defmodule Chess.Notation.UCITest do
  use ExUnit.Case, async: true

  alias Chess.Move
  alias Chess.Notation.UCI
  alias Chess.Position
  alias Chess.Square

  defp move(from, to, promotion \\ nil),
    do: Move.new(Square.from_algebraic(from), Square.from_algebraic(to), promotion)

  test "resolves legal coordinate moves against the position" do
    start = Position.starting_position()

    assert UCI.parse_move(start, "e2e4") == {:ok, move("e2", "e4")}
    assert UCI.parse_move(start, "g1f3") == {:ok, move("g1", "f3")}
  end

  test "rejects illegal, malformed and out-of-turn moves" do
    start = Position.starting_position()

    assert UCI.parse_move(start, "e2e5") == :error
    assert UCI.parse_move(start, "e7e5") == :error
    assert UCI.parse_move(start, "e2e4x") == :error
    assert UCI.parse_move(start, "z9z1") == :error
    assert UCI.parse_move(start, "e2e4q") == :error
    assert UCI.parse_move(start, "") == :error
  end

  test "resolves promotions only with the matching promotion piece" do
    position =
      Position.new()
      |> Position.put_piece(Square.from_algebraic("e1"), {:white, :king})
      |> Position.put_piece(Square.from_algebraic("e8"), {:black, :king})
      |> Position.put_piece(Square.from_algebraic("a7"), {:white, :pawn})

    assert UCI.parse_move(position, "a7a8q") == {:ok, move("a7", "a8", :queen)}
    assert UCI.parse_move(position, "a7a8n") == {:ok, move("a7", "a8", :knight)}
    assert UCI.parse_move(position, "a7a8") == :error
    assert UCI.parse_move(position, "a7a8k") == :error
  end

  test "renders a principal variation as SAN and stops at the first bad move" do
    start = Position.starting_position()

    assert UCI.pv_to_san(start, "e2e4 e7e5 g1f3 b8c6") == ["e4", "e5", "Nf3", "Nc6"]
    assert UCI.pv_to_san(start, "e2e4 e7e5 g1g3") == ["e4", "e5"]
    assert UCI.pv_to_san(start, "e7e5") == []
    assert UCI.pv_to_san(start, "") == []
  end

  test "renders castling in a principal variation" do
    start = Position.starting_position()

    assert UCI.pv_to_san(start, "e2e4 e7e5 g1f3 b8c6 f1e2 g8f6 e1g1") == [
             "e4",
             "e5",
             "Nf3",
             "Nc6",
             "Be2",
             "Nf6",
             "O-O"
           ]
  end
end
