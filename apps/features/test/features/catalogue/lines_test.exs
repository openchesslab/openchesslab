defmodule Features.Catalogue.LinesTest do
  use ExUnit.Case, async: true

  @start "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

  defp extract(fen), do: Features.extract(fen).features

  test "start position" do
    features = extract(@start)

    assert features["lines.open_files"] == []
    assert features["lines.semi_open_files"] == %{"white" => [], "black" => []}
    assert features["lines.closed_files"] == ~w(a b c d e f g h)
    assert features["lines.open_ranks"] == [1, 3, 4, 5, 6, 8]
    assert features["lines.rook_open_file"] == %{"white" => false, "black" => false}
    assert features["lines.rook_semi_open_file"] == %{"white" => false, "black" => false}
    assert features["lines.battery_on_file"] == %{"white" => false, "black" => false}
    assert features["lines.battery_on_diagonal"] == %{"white" => false, "black" => false}
    assert features["lines.queen_rook_battery"] == %{"white" => false, "black" => false}
    assert features["lines.penetration"] == %{"white" => false, "black" => false}
    assert features["lines.xray"]["white"]
  end

  test "diagonal features name full diagonals by their true endpoints" do
    features = extract(@start)

    # Startpos: diagonals avoiding rank 2 are free of white pawns; each of
    # them also crosses a black pawn on rank 7 (semi-open too). Labels name
    # the whole diagonal ("a3f8" is a3–f8), not just its first two squares.
    assert "a3f8" in features["lines.open_diagonals"]["white"]
    assert "a5d8" in features["lines.open_diagonals"]["white"]
    assert "a7b8" in features["lines.open_diagonals"]["white"]
    refute "a3b4" in features["lines.open_diagonals"]["white"]
    refute "a5b6" in features["lines.open_diagonals"]["white"]

    assert features["lines.open_diagonals"] == features["lines.semi_open_diagonals"]

    # Long diagonals have at least five squares.
    assert features["lines.long_diagonals"]["white"] |> Enum.sort() ==
             ~w(a3f8 a4e8 h3c8 h4d8)

    # A diagonal blocked by an own pawn is neither open nor semi-open.
    refute "c1h6" in features["lines.open_diagonals"]["white"]
  end

  test "open files and rook batteries" do
    features = extract("4k3/8/8/8/8/8/8/R3K3 w - - 0 1")
    assert features["lines.open_files"] == ~w(a b c d e f g h)
    assert features["lines.rook_open_file"]["white"]

    features = extract("R7/R3K3/8/8/8/8/8/4k3 w - - 0 1")
    assert features["lines.rook_open_file"]["white"]
    assert features["lines.battery_on_file"]["white"]
  end
end
