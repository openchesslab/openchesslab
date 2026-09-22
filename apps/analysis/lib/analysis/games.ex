defmodule Analysis.Games do
  @moduledoc false

  alias Analysis.Game
  alias Analysis.GameEvents
  alias Analysis.GameStore.Memory
  alias Analysis.Node
  alias Analysis.PositionStore
  alias Chess.Move
  alias Chess.Position

  @store Analysis.GameStore.Runtime

  @spec insert(Game.t()) ::
          {:ok, pos_integer()} | {:error, :already_exists}
  def insert(%Game{} = game) do
    Memory.insert(@store, game)
  end

  @spec get(Game.id()) ::
          {:ok, Game.t(), pos_integer()} | :not_found
  def get(game_id) do
    Memory.get(@store, game_id)
  end

  @spec play(Game.id(), Game.path(), Move.t()) ::
          {:ok, Game.t(), pos_integer(), Game.path()}
          | {:error,
             :game_not_found
             | :node_not_found
             | :position_not_found
             | :illegal_move
             | :conflict}
  def play(game_id, path, %Move{} = move) do
    case get(game_id) do
      {:ok, game, revision} ->
        play(game, revision, path, move)

      :not_found ->
        {:error, :game_not_found}
    end
  end

  @spec set_comment(Game.id(), Game.path(), String.t() | nil) ::
          {:ok, Game.t(), pos_integer()}
          | {:error, :game_not_found | :node_not_found | :conflict}
  def set_comment(game_id, path, comment) do
    case get(game_id) do
      {:ok, game, revision} ->
        set_comment(game, revision, path, comment)

      :not_found ->
        {:error, :game_not_found}
    end
  end

  defp set_comment(game, revision, path, comment) do
    with {:ok, updated_game} <- Game.set_comment(game, path, comment),
         {:ok, new_revision} <- persist(updated_game, revision) do
      {:ok, updated_game, new_revision}
    end
  end

  defp play(game, revision, path, move) do
    with %Node{} = node <- Game.node_at(game, path),
         {:ok, position} <- PositionStore.get(Node.position_id(node)),
         {:ok, next_position} <- Position.apply_move(position, move) do
      position_id = PositionStore.append(next_position)
      updated_game = Game.add_child(game, path, move, position_id)

      child_index =
        updated_game
        |> Game.node_at(path)
        |> Node.child_index(move)

      resulting_path = path ++ [child_index]

      case persist(updated_game, revision) do
        {:ok, new_revision} ->
          {:ok, updated_game, new_revision, resulting_path}

        {:error, _reason} = error ->
          error
      end
    else
      nil ->
        {:error, :node_not_found}

      :not_found ->
        {:error, :position_not_found}

      {:error, :illegal_move} = error ->
        error
    end
  end

  defp persist(game, revision) do
    case Memory.update(@store, game, revision) do
      {:ok, new_revision} ->
        :ok = GameEvents.publish_changed(game.id)
        {:ok, new_revision}

      {:error, :conflict} ->
        {:error, :conflict}

      {:error, :not_found} ->
        {:error, :game_not_found}
    end
  end
end
