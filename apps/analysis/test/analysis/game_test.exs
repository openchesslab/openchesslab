defmodule Analysis.GameTest do
  use ExUnit.Case, async: true

  alias Analysis.Game

  describe "new/1" do
    test "stores the initial position id" do
      game = Game.new(42)

      assert game.initial_position_id == 42
    end

    test "starts with empty metadata" do
      game = Game.new(42)

      assert game.metadata == %{}
    end

    test "starts with an empty main variation" do
      game = Game.new(42)

      assert game.main_variation.transitions == []
    end
  end

  describe "new/2" do
    test "stores the initial position id" do
      game = Game.new(42, %{event: "World Championship"})

      assert game.initial_position_id == 42
    end

    test "stores metadata" do
      metadata = %{
        event: "World Championship",
        site: "Amsterdam",
        round: "1"
      }

      game = Game.new(42, metadata)

      assert game.metadata == metadata
    end

    test "starts with an empty main variation" do
      game = Game.new(42, %{event: "World Championship"})

      assert game.main_variation.transitions == []
    end
  end
end
