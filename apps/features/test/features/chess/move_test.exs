defmodule Features.Chess.MoveTest do
  use ExUnit.Case, async: true

  alias Features.Chess.Move

  test "to_uci without promotion" do
    assert Move.to_uci(Move.new(12, 28)) == "e2e4"
    assert Move.to_uci(Move.new(0, 7)) == "a1h1"
  end

  test "to_uci with promotion uses UCI letters" do
    assert Move.to_uci(Move.new(48, 56, :queens)) == "a7a8q"
    assert Move.to_uci(Move.new(48, 56, :rooks)) == "a7a8r"
    assert Move.to_uci(Move.new(48, 56, :bishops)) == "a7a8b"
    assert Move.to_uci(Move.new(48, 56, :knights)) == "a7a8n"
  end

  test "new defaults promotion to nil" do
    assert Move.new(12, 28).promotion == nil
  end
end
