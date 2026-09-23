defmodule Analysis.GameStore.MemoryTest do
  use ExUnit.Case, async: true

  alias Analysis.Game
  alias Analysis.GameStore.Memory

  setup do
    {:ok, store} = Memory.start_link()

    %{store: store}
  end

  describe "insert/2" do
    test "stores a game with revision 1", %{store: store} do
      game = Game.new("game-1", :p0)

      assert {:ok, 1} = Memory.insert(store, game)
      assert {:ok, ^game, 1} = Memory.get(store, "game-1")
    end

    test "does not overwrite an existing game", %{store: store} do
      game = Game.new("game-1", :p0)
      other = Game.new("game-1", :other)

      assert {:ok, 1} = Memory.insert(store, game)
      assert {:error, :already_exists} = Memory.insert(store, other)

      assert {:ok, ^game, 1} = Memory.get(store, "game-1")
    end
  end

  describe "get/2" do
    test "returns :not_found for an unknown game", %{store: store} do
      assert :not_found = Memory.get(store, "missing")
    end
  end

  describe "list/1" do
    test "returns all stored games with their revisions", %{store: store} do
      game_1 = Game.new("game-1", :p0)
      game_2 = Game.new("game-2", :p1)

      assert {:ok, 1} = Memory.insert(store, game_1)
      assert {:ok, 1} = Memory.insert(store, game_2)

      assert MapSet.new(Memory.list(store)) ==
               MapSet.new([
                 {game_1, 1},
                 {game_2, 1}
               ])
    end

    test "returns the current revision", %{store: store} do
      game = Game.new("game-1", :p0)

      assert {:ok, 1} = Memory.insert(store, game)

      updated_game =
        %{game | metadata: %{event: "Candidates"}}

      assert {:ok, 2} =
               Memory.update(store, updated_game, 1)

      assert Memory.list(store) == [
               {updated_game, 2}
             ]
    end

    test "returns an empty list for an empty store", %{store: store} do
      assert Memory.list(store) == []
    end
  end

  describe "update/3" do
    test "replaces a game when the expected revision matches",
         %{store: store} do
      game = Game.new("game-1", :p0)

      {:ok, revision} = Memory.insert(store, game)

      updated_game = %{game | metadata: %{event: "Candidates"}}

      assert {:ok, 2} =
               Memory.update(store, updated_game, revision)

      assert {:ok, ^updated_game, 2} =
               Memory.get(store, "game-1")
    end

    test "rejects an update with a stale revision",
         %{store: store} do
      game = Game.new("game-1", :p0)

      {:ok, revision} = Memory.insert(store, game)

      first_update = %{game | metadata: %{version: 1}}

      {:ok, new_revision} =
        Memory.update(store, first_update, revision)

      stale_update = %{game | metadata: %{version: 2}}

      assert {:error, :conflict} =
               Memory.update(store, stale_update, revision)

      assert {:ok, ^first_update, ^new_revision} =
               Memory.get(store, "game-1")
    end

    test "returns not_found for an unknown game",
         %{store: store} do
      game = Game.new("missing", :p0)

      assert {:error, :not_found} =
               Memory.update(store, game, 1)
    end
  end

  describe "delete/3" do
    test "deletes a game when the expected revision matches",
         %{store: store} do
      game = Game.new("game-1", :p0)

      {:ok, revision} = Memory.insert(store, game)

      assert :ok =
               Memory.delete(store, "game-1", revision)

      assert :not_found = Memory.get(store, "game-1")
    end

    test "rejects deletion with a stale revision",
         %{store: store} do
      game = Game.new("game-1", :p0)

      {:ok, revision} = Memory.insert(store, game)

      updated_game = %{game | metadata: %{version: 2}}

      {:ok, new_revision} =
        Memory.update(store, updated_game, revision)

      assert {:error, :conflict} =
               Memory.delete(store, "game-1", revision)

      assert {:ok, ^updated_game, ^new_revision} =
               Memory.get(store, "game-1")
    end

    test "returns not_found for an unknown game",
         %{store: store} do
      assert {:error, :not_found} =
               Memory.delete(store, "missing", 1)
    end
  end
end
