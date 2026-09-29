defmodule Web.ChessComponentsTest do
  use ExUnit.Case, async: true

  alias Web.ChessComponents

  defp square(square, color), do: %{type: :square, square: square, color: color}

  test "a lone square keeps all four sides" do
    sides = ChessComponents.highlight_sides([square(27, "blue")])

    assert sides == %{{27, "blue"} => [:top, :right, :bottom, :left]}
  end

  test "adjacent same-colour squares drop the shared side" do
    sides = ChessComponents.highlight_sides([square(27, "blue"), square(28, "blue")])

    assert sides[{27, "blue"}] == [:top, :bottom, :left]
    assert sides[{28, "blue"}] == [:top, :right, :bottom]
  end

  test "an L-shape keeps its outline and drops the shared edges" do
    # d4 + e4 + e5
    sides =
      ChessComponents.highlight_sides([
        square(27, "blue"),
        square(28, "blue"),
        square(36, "blue")
      ])

    assert sides[{27, "blue"}] == [:top, :bottom, :left]
    assert sides[{28, "blue"}] == [:right, :bottom]
    assert sides[{36, "blue"}] == [:top, :right, :left]
  end

  test "a 2x2 block is one square outline" do
    sides =
      ChessComponents.highlight_sides([
        square(27, "blue"),
        square(28, "blue"),
        square(35, "blue"),
        square(36, "blue")
      ])

    assert sides[{27, "blue"}] == [:bottom, :left]
    assert sides[{28, "blue"}] == [:right, :bottom]
    assert sides[{35, "blue"}] == [:top, :left]
    assert sides[{36, "blue"}] == [:top, :right]
  end

  test "different colours never merge" do
    sides = ChessComponents.highlight_sides([square(27, "blue"), square(28, "red")])

    assert sides[{27, "blue"}] == [:top, :right, :bottom, :left]
    assert sides[{28, "red"}] == [:top, :right, :bottom, :left]
  end

  test "file and rank edges never wrap around" do
    # a1, b1, a2
    sides =
      ChessComponents.highlight_sides([
        square(0, "green"),
        square(1, "green"),
        square(8, "green")
      ])

    assert sides[{0, "green"}] == [:bottom, :left]
    assert sides[{1, "green"}] == [:top, :right, :bottom]
    assert sides[{8, "green"}] == [:top, :right, :left]
  end

  test "arrows and other shapes are ignored" do
    sides =
      ChessComponents.highlight_sides([
        %{type: :arrow, from: 12, to: 28, color: "blue"},
        square(27, "blue")
      ])

    assert sides == %{{27, "blue"} => [:top, :right, :bottom, :left]}
  end
end
