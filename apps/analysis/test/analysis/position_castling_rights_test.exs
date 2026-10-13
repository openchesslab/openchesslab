defmodule Analysis.PositionCastlingRightsTest do
  use ExUnit.Case, async: true

  alias Analysis.PositionPropertyKeyCodec

  test "encodes every castling right as a distinct stable key" do
    assert PositionPropertyKeyCodec.encode(:castling_right, :white_kingside) ==
             {:ok, <<7, 0>>}

    assert PositionPropertyKeyCodec.encode(:castling_right, :white_queenside) ==
             {:ok, <<7, 1>>}

    assert PositionPropertyKeyCodec.encode(:castling_right, :black_kingside) ==
             {:ok, <<7, 2>>}

    assert PositionPropertyKeyCodec.encode(:castling_right, :black_queenside) ==
             {:ok, <<7, 3>>}
  end

  test "rejects invalid castling rights" do
    for value <- [:white, :black, :kingside, nil, false, 0, "white_kingside"] do
      assert PositionPropertyKeyCodec.encode(:castling_right, value) ==
               {:error, :invalid_castling_right}
    end
  end

  test "castling rights cannot collide with existing property types" do
    {:ok, castling_key} =
      PositionPropertyKeyCodec.encode(:castling_right, :white_kingside)

    {:ok, check_key} = PositionPropertyKeyCodec.encode(:in_check, :white)
    {:ok, side_key} = PositionPropertyKeyCodec.encode(:side_to_move, :white)
    {:ok, open_key} = PositionPropertyKeyCodec.encode(:open_files, :e)

    assert MapSet.size(MapSet.new([castling_key, check_key, side_key, open_key])) == 4
  end
end
