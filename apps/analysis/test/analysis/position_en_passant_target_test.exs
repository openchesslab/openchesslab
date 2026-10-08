defmodule Analysis.PositionEnPassantTargetTest do
  use ExUnit.Case, async: true

  alias Analysis.PositionPropertyKeyCodec
  alias Chess.Square

  test "encodes en passant target squares as stable keys" do
    assert PositionPropertyKeyCodec.encode(:en_passant_target, 0) ==
             {:ok, <<8, 0>>}

    assert PositionPropertyKeyCodec.encode(
             :en_passant_target,
             Square.from_algebraic("e3")
           ) == {:ok, <<8, 20>>}

    assert PositionPropertyKeyCodec.encode(
             :en_passant_target,
             Square.from_algebraic("e6")
           ) == {:ok, <<8, 44>>}

    assert PositionPropertyKeyCodec.encode(:en_passant_target, 63) ==
             {:ok, <<8, 63>>}
  end

  test "rejects invalid en passant target values" do
    for value <- [nil, -1, 64, :e3, "e3", 20.0, true, {:white, 20}] do
      assert PositionPropertyKeyCodec.encode(:en_passant_target, value) ==
               {:error, :invalid_en_passant_target}
    end
  end

  test "en passant target keys do not collide with existing properties" do
    {:ok, target_key} =
      PositionPropertyKeyCodec.encode(
        :en_passant_target,
        Square.from_algebraic("e3")
      )

    {:ok, castling_key} =
      PositionPropertyKeyCodec.encode(:castling_right, :white_kingside)

    {:ok, check_key} = PositionPropertyKeyCodec.encode(:in_check, :white)
    {:ok, turn_key} = PositionPropertyKeyCodec.encode(:side_to_move, :black)

    assert MapSet.size(MapSet.new([target_key, castling_key, check_key, turn_key])) == 4
  end
end
