defmodule Analysis.GameStore.DetsTest do
  use ExUnit.Case, async: false

  alias Analysis.Game
  alias Analysis.GameStore.Dets

  setup do
    path =
      Path.join(
        System.tmp_dir!(),
        "openchesslab-game-store-#{System.unique_integer([:positive])}.dets"
      )

    on_exit(fn ->
      File.rm(path)
    end)

    %{path: path}
  end

  test "inserts and retrieves a game", %{path: path} do
    {:ok, store} = Dets.start_link(path)
    game = Game.new("game-1", :p0)

    assert {:ok, 1} = Dets.insert(store, game)
    assert {:ok, ^game, 1} = Dets.get(store, "game-1")

    GenServer.stop(store)
  end

  test "does not overwrite an existing game", %{path: path} do
    {:ok, store} = Dets.start_link(path)

    game = Game.new("game-1", :p0)
    other = Game.new("game-1", :other)

    assert {:ok, 1} = Dets.insert(store, game)
    assert {:error, :already_exists} = Dets.insert(store, other)

    assert {:ok, ^game, 1} = Dets.get(store, "game-1")

    GenServer.stop(store)
  end

  test "returns not_found for an unknown game", %{path: path} do
    {:ok, store} = Dets.start_link(path)

    assert :not_found = Dets.get(store, "missing")

    GenServer.stop(store)
  end

  test "updates a game when the revision matches", %{path: path} do
    {:ok, store} = Dets.start_link(path)

    game = Game.new("game-1", :p0)
    {:ok, revision} = Dets.insert(store, game)

    updated_game = %{game | metadata: %{event: "Candidates"}}

    assert {:ok, 2} =
             Dets.update(store, updated_game, revision)

    assert {:ok, ^updated_game, 2} =
             Dets.get(store, "game-1")

    GenServer.stop(store)
  end

  test "rejects an update with a stale revision", %{path: path} do
    {:ok, store} = Dets.start_link(path)

    game = Game.new("game-1", :p0)
    {:ok, revision} = Dets.insert(store, game)

    first_update = %{game | metadata: %{version: 1}}

    assert {:ok, new_revision} =
             Dets.update(store, first_update, revision)

    stale_update = %{game | metadata: %{version: 2}}

    assert {:error, :conflict} =
             Dets.update(store, stale_update, revision)

    assert {:ok, ^first_update, ^new_revision} =
             Dets.get(store, "game-1")

    GenServer.stop(store)
  end

  test "returns not_found when updating an unknown game", %{path: path} do
    {:ok, store} = Dets.start_link(path)

    game = Game.new("missing", :p0)

    assert {:error, :not_found} =
             Dets.update(store, game, 1)

    GenServer.stop(store)
  end

  test "deletes a game when the revision matches", %{path: path} do
    {:ok, store} = Dets.start_link(path)

    game = Game.new("game-1", :p0)
    {:ok, revision} = Dets.insert(store, game)

    assert :ok = Dets.delete(store, "game-1", revision)
    assert :not_found = Dets.get(store, "game-1")

    GenServer.stop(store)
  end

  test "rejects deletion with a stale revision", %{path: path} do
    {:ok, store} = Dets.start_link(path)

    game = Game.new("game-1", :p0)
    {:ok, revision} = Dets.insert(store, game)

    updated_game = %{game | metadata: %{version: 2}}

    {:ok, new_revision} =
      Dets.update(store, updated_game, revision)

    assert {:error, :conflict} =
             Dets.delete(store, "game-1", revision)

    assert {:ok, ^updated_game, ^new_revision} =
             Dets.get(store, "game-1")

    GenServer.stop(store)
  end

  test "returns not_found when deleting an unknown game", %{path: path} do
    {:ok, store} = Dets.start_link(path)

    assert {:error, :not_found} =
             Dets.delete(store, "missing", 1)

    GenServer.stop(store)
  end

  test "persists a game and revision across store restarts", %{path: path} do
    {:ok, store} = Dets.start_link(path)

    game =
      Game.new(
        "game-1",
        :p0,
        %{event: "World Championship"}
      )

    {:ok, game} =
      Game.set_comment(game, [], "Persistent analysis")

    assert {:ok, 1} = Dets.insert(store, game)

    updated_game =
      %{game | metadata: Map.put(game.metadata, :round, "1")}

    assert {:ok, 2} =
             Dets.update(store, updated_game, 1)

    GenServer.stop(store)

    {:ok, store} = Dets.start_link(path)

    assert {:ok, ^updated_game, 2} =
             Dets.get(store, "game-1")

    continued_game =
      %{updated_game | metadata: Map.put(updated_game.metadata, :site, "London")}

    assert {:ok, 3} =
             Dets.update(store, continued_game, 2)

    assert {:ok, ^continued_game, 3} =
             Dets.get(store, "game-1")

    GenServer.stop(store)
  end
end
