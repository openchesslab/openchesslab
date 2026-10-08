defmodule Analysis.PositionInCheckTest do
  use ExUnit.Case, async: true

  alias Analysis.PositionPropertyKeyCodec

  test "encodes a checked king per color" do
    assert PositionPropertyKeyCodec.encode(:in_check, :white) ==
             {:ok, <<6, 0>>}

    assert PositionPropertyKeyCodec.encode(:in_check, :black) ==
             {:ok, <<6, 1>>}
  end

  test "rejects invalid checked-king search keys" do
    for value <- [:red, :both, nil, false, 0, "white", {:white, true}] do
      assert PositionPropertyKeyCodec.encode(:in_check, value) ==
               {:error, :invalid_in_check}
    end
  end

  test "check status keys differ from existing position property keys" do
    {:ok, white_check} = PositionPropertyKeyCodec.encode(:in_check, :white)
    {:ok, black_check} = PositionPropertyKeyCodec.encode(:in_check, :black)
    {:ok, white_turn} = PositionPropertyKeyCodec.encode(:side_to_move, :white)
    {:ok, white_outpost} = PositionPropertyKeyCodec.encode(:outposts, {:white, 36})

    assert MapSet.size(MapSet.new([white_check, black_check, white_turn, white_outpost])) == 4
  end
end
