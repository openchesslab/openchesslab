defmodule Analysis.PositionSideToMoveTest do
  use ExUnit.Case, async: true

  alias Analysis.PositionPropertyKeyCodec

  test "encodes both sides to move as distinct stable keys" do
    assert PositionPropertyKeyCodec.encode(:side_to_move, :white) ==
             {:ok, <<5, 0>>}

    assert PositionPropertyKeyCodec.encode(:side_to_move, :black) ==
             {:ok, <<5, 1>>}
  end

  test "rejects invalid sides to move" do
    for value <- [:red, :both, nil, 0, "white", {:white, :e}] do
      assert PositionPropertyKeyCodec.encode(:side_to_move, value) ==
               {:error, :invalid_side_to_move}
    end
  end

  test "side-to-move keys do not collide with existing feature types" do
    {:ok, side_key} =
      PositionPropertyKeyCodec.encode(:side_to_move, :white)

    {:ok, outpost_key} =
      PositionPropertyKeyCodec.encode(:outposts, {:white, 36})

    {:ok, semi_open_key} =
      PositionPropertyKeyCodec.encode(:semi_open_files, {:white, :e})

    {:ok, open_key} =
      PositionPropertyKeyCodec.encode(:open_files, :e)

    assert MapSet.size(MapSet.new([side_key, outpost_key, semi_open_key, open_key])) == 4
  end
end
