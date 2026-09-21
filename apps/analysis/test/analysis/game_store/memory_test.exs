defmodule Analysis.GameStore.MemoryTest do
  use ExUnit.Case, async: true

  alias Analysis.Game
  alias Analysis.GameStore.Memory

  describe "insert/2" do
    test "stores a game with revision 1" do
      store = Memory.new()
      game = Game.new("game-1", :p0)

      assert {:ok, store, 1} = Memory.insert(store, game)
      assert {:ok, ^game, 1} = Memory.get(store, "game-1")
    end

    test "does not overwrite an existing game" do
      store = Memory.new()
      game = Game.new("game-1", :p0)

      assert {:ok, store, 1} = Memory.insert(store, game)
      assert {:error, :already_exists} = Memory.insert(store, game)

      assert {:ok, ^game, 1} = Memory.get(store, "game-1")
    end
  end

  describe "get/2" do
    test "returns :not_found for an unknown game" do
      assert :not_found = Memory.get(Memory.new(), "missing")
    end
  end

  describe "update/3" do
    test "replaces a game when the expected revision matches" do
      game = Game.new("game-1", :p0)

      {:ok, store, revision} =
        Memory.new()
        |> Memory.insert(game)

      updated_game = %{game | metadata: %{event: "Candidates"}}

      assert {:ok, store, 2} =
               Memory.update(store, updated_game, revision)

      assert {:ok, ^updated_game, 2} =
               Memory.get(store, "game-1")
    end

    test "rejects an update with a stale revision" do
      game = Game.new("game-1", :p0)

      {:ok, store, revision} =
        Memory.new()
        |> Memory.insert(game)

      first_update = %{game | metadata: %{version: 1}}

      {:ok, store, new_revision} =
        Memory.update(store, first_update, revision)

      stale_update = %{game | metadata: %{version: 2}}

      assert {:error, :conflict} =
               Memory.update(store, stale_update, revision)

      assert {:ok, ^first_update, ^new_revision} =
               Memory.get(store, "game-1")
    end

    test "returns not_found for an unknown game" do
      game = Game.new("missing", :p0)

      assert {:error, :not_found} =
               Memory.update(Memory.new(), game, 1)
    end
  end

  describe "delete/3" do
    test "deletes a game when the expected revision matches" do
      game = Game.new("game-1", :p0)

      {:ok, store, revision} =
        Memory.new()
        |> Memory.insert(game)

      assert {:ok, store} =
               Memory.delete(store, "game-1", revision)

      assert :not_found = Memory.get(store, "game-1")
    end

    test "rejects deletion with a stale revision" do
      game = Game.new("game-1", :p0)

      {:ok, store, revision} =
        Memory.new()
        |> Memory.insert(game)

      updated_game = %{game | metadata: %{version: 2}}

      {:ok, store, new_revision} =
        Memory.update(store, updated_game, revision)

      assert {:error, :conflict} =
               Memory.delete(store, "game-1", revision)

      assert {:ok, ^updated_game, ^new_revision} =
               Memory.get(store, "game-1")
    end

    test "returns not_found for an unknown game" do
      assert {:error, :not_found} =
               Memory.delete(Memory.new(), "missing", 1)
    end
  end
end
