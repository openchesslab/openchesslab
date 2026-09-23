defmodule Analysis.PositionRecordCodecTest do
  use ExUnit.Case, async: true

  alias Analysis.PositionRecordCodec
  alias Chess.Position

  test "has a stable versioned format id" do
    assert PositionRecordCodec.format_id() ==
             <<"chess-position-v1">>
  end

  test "uses the chess position record size" do
    assert PositionRecordCodec.record_size() == 67
  end

  test "round trips a chess position" do
    position =
      Position.starting_position()

    assert {:ok, encoded} =
             PositionRecordCodec.encode(position)

    assert byte_size(encoded) ==
             PositionRecordCodec.record_size()

    assert PositionRecordCodec.decode(encoded) ==
             {:ok, position}
  end

  test "rejects a value that is not a chess position" do
    assert PositionRecordCodec.encode(:not_a_position) ==
             {:error, :invalid_position}
  end

  test "propagates invalid encoded records" do
    assert PositionRecordCodec.decode(<<1, 2, 3>>) ==
             {:error, :invalid_record_size}
  end

  test "rejects a value that is not binary" do
    assert PositionRecordCodec.decode(:not_a_record) ==
             {:error, :invalid_record}
  end
end
