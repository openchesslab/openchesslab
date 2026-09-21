defmodule Analysis.GamesTest do
  use ExUnit.Case, async: false

  alias Analysis.Game
  alias Analysis.Games
  alias Analysis.Node
  alias Analysis.PositionStore
  alias Chess.Move
  alias Chess.Position
  alias Chess.Square

  defp move(from, to) do
    Move.new(
      Square.from_algebraic(from),
      Square.from_algebraic(to)
    )
  end

  setup do
    game_id = "game-#{System.unique_integer([:positive])}"

    %{game_id: game_id}
  end

  test "gets a stored game", %{game_id: game_id} do
    game = Game.new(game_id, 42)

    assert {:ok, 1} = Games.insert(game)

    assert {:ok, ^game, 1} = Games.get(game_id)
  end

  test "returns not_found for an unknown game", %{game_id: game_id} do
    assert :not_found = Games.get(game_id)
  end

  test "does not insert the same game twice", %{game_id: game_id} do
    game = Game.new(game_id, 42)

    assert {:ok, 1} = Games.insert(game)
    assert {:error, :already_exists} = Games.insert(game)
  end

  test "plays a move and persists the updated game", %{game_id: game_id} do
    position_id = PositionStore.append(Position.starting_position())
    game = Game.new(game_id, position_id)

    assert {:ok, 1} = Games.insert(game)

    assert {:ok, updated_game, 2, [0]} =
             Games.play(game_id, [], move("e2", "e4"))

    child = Game.node_at(updated_game, [0])

    assert %Node{} = child
    assert Node.move(child) == move("e2", "e4")

    assert {:ok, ^updated_game, 2} = Games.get(game_id)

    assert {:ok, position} =
             PositionStore.get(Node.position_id(child))

    assert Position.piece_at(
             position,
             Square.from_algebraic("e4")
           ) == {:white, :pawn}

    assert position.side_to_move == :black
  end

  test "returns game_not_found for an unknown game", %{game_id: game_id} do
    assert Games.play(game_id, [], move("e2", "e4")) ==
             {:error, :game_not_found}
  end

  test "returns node_not_found for an unknown path", %{game_id: game_id} do
    position_id = PositionStore.append(Position.starting_position())
    game = Game.new(game_id, position_id)

    assert {:ok, 1} = Games.insert(game)

    assert Games.play(game_id, [0], move("e2", "e4")) ==
             {:error, :node_not_found}

    assert {:ok, ^game, 1} = Games.get(game_id)
  end

  test "returns position_not_found when the node position does not exist", %{
    game_id: game_id
  } do
    game = Game.new(game_id, 999_999_999)

    assert {:ok, 1} = Games.insert(game)

    assert Games.play(game_id, [], move("e2", "e4")) ==
             {:error, :position_not_found}

    assert {:ok, ^game, 1} = Games.get(game_id)
  end

  test "returns illegal_move without updating the game", %{game_id: game_id} do
    position_id = PositionStore.append(Position.starting_position())
    game = Game.new(game_id, position_id)

    assert {:ok, 1} = Games.insert(game)

    assert Games.play(game_id, [], move("e2", "e5")) ==
             {:error, :illegal_move}

    assert {:ok, ^game, 1} = Games.get(game_id)
  end

  test "playing an existing continuation does not duplicate it", %{
    game_id: game_id
  } do
    position_id = PositionStore.append(Position.starting_position())
    game = Game.new(game_id, position_id)

    assert {:ok, 1} = Games.insert(game)

    assert {:ok, _game, 2, [0]} =
             Games.play(game_id, [], move("e2", "e4"))

    assert {:ok, game, 3, [0]} =
             Games.play(game_id, [], move("e2", "e4"))

    assert length(Node.children(Game.root(game))) == 1
  end
end
