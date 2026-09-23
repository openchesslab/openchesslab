defmodule Analysis.PositionExactKeyHashTest do
  use ExUnit.Case, async: true

  alias Analysis.PositionExactKeyHash

  alias Chess.Position
  alias Chess.PositionHash
  alias Chess.PositionKey

  test "has a stable versioned format id" do
    assert PositionExactKeyHash.format_id() ==
             <<"chess-position-exact-sha256-v1">>
  end

  test "uses a 256 bit hash" do
    assert PositionExactKeyHash.hash_size() ==
             32
  end

  test "hashes a chess exact position key" do
    key =
      Position.starting_position()
      |> PositionKey.exact()

    assert PositionExactKeyHash.hash(key) ==
             {:ok, PositionHash.hash(key)}
  end

  test "returns hashes with the declared size" do
    key =
      Position.starting_position()
      |> PositionKey.exact()

    assert {:ok, hash} =
             PositionExactKeyHash.hash(key)

    assert byte_size(hash) ==
             PositionExactKeyHash.hash_size()
  end

  test "rejects a value that is not a binary exact key" do
    assert PositionExactKeyHash.hash(:not_a_key) ==
             {:error, :invalid_exact_key}
  end
end
