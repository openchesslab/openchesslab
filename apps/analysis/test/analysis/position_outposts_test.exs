defmodule Analysis.PositionOutpostsTest do
  use ExUnit.Case, async: true

  alias Analysis.PositionPropertyKeyCodec
  alias Chess.Square

  test "encodes knight outposts by color and board square" do
    e5 = Square.from_algebraic("e5")
    d4 = Square.from_algebraic("d4")

    assert PositionPropertyKeyCodec.encode(:outposts, {:white, e5}) ==
             {:ok, <<4, 0, e5>>}

    assert PositionPropertyKeyCodec.encode(:outposts, {:black, d4}) ==
             {:ok, <<4, 1, d4>>}

    assert PositionPropertyKeyCodec.encode(:outposts, {:black, e5}) ==
             {:ok, <<4, 1, e5>>}
  end

  test "rejects invalid outpost search keys" do
    for value <- [
          {:red, 36},
          {:white, -1},
          {:white, 64},
          {:white, :e5},
          {nil, 36},
          :e5,
          nil
        ] do
      assert PositionPropertyKeyCodec.encode(:outposts, value) ==
               {:error, :invalid_outpost}
    end
  end

  test "outpost keys do not collide with existing property types" do
    square = Square.from_algebraic("e5")

    assert {:ok, outpost_key} =
             PositionPropertyKeyCodec.encode(:outposts, {:white, square})

    assert {:ok, semi_open_key} =
             PositionPropertyKeyCodec.encode(:semi_open_files, {:white, :e})

    assert {:ok, open_key} =
             PositionPropertyKeyCodec.encode(:open_files, :e)

    assert MapSet.size(MapSet.new([outpost_key, semi_open_key, open_key])) == 3
  end
end
