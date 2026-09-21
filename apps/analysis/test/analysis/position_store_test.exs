defmodule Analysis.PositionStoreTest do
  use ExUnit.Case, async: false

  alias Analysis.PositionStore
  alias Chess.Position

  test "appends and gets a position" do
    position = Position.starting_position()

    position_id = PositionStore.append(position)

    assert {:ok, ^position} = PositionStore.get(position_id)
  end

  test "returns not_found for an unknown position" do
    assert :not_found = PositionStore.get(999_999_999)
  end

  test "reuses the id of an existing position" do
    position = Position.starting_position()

    first_id = PositionStore.append(position)
    second_id = PositionStore.append(position)

    assert second_id == first_id
  end
end
