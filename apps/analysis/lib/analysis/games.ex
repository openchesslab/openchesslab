defmodule Analysis.Games do
  @moduledoc false

  alias Analysis.Game
  alias Analysis.GameEvents
  alias Analysis.GameStore
  alias Analysis.Node
  alias Analysis.PositionStore
  alias Analysis.Transition
  alias Chess.Move
  alias Chess.Position
  alias Chess.PositionDraft

  @type position_store_error ::
          {:position_store, term()}

  @spec create(Game.id()) ::
          {:ok, Game.t(), pos_integer()}
          | {:error,
             :already_exists
             | position_store_error()}
  def create(game_id) do
    case append_position(Position.starting_position()) do
      {:ok, position_id} ->
        game =
          Game.new(
            game_id,
            position_id
          )

        case insert(game) do
          {:ok, revision} ->
            {:ok, game, revision}

          {:error, :already_exists} = error ->
            error
        end

      {:error, _reason} = error ->
        error
    end
  end

  @spec insert(Game.t()) ::
          {:ok, pos_integer()} | {:error, :already_exists}
  def insert(%Game{} = game) do
    GameStore.insert(game)
  end

  @spec get(Game.id()) ::
          {:ok, Game.t(), pos_integer()} | :not_found
  def get(game_id) do
    GameStore.get(game_id)
  end

  @spec list() :: [{Game.t(), pos_integer()}]
  def list do
    GameStore.list()
  end

  @spec play(Game.id(), Game.path(), Move.t()) ::
          {:ok, Game.t(), pos_integer(), Game.path()}
          | {:error,
             :game_not_found
             | :node_not_found
             | :position_not_found
             | :illegal_move
             | :conflict
             | position_store_error()}
  def play(game_id, path, %Move{} = move) do
    case get(game_id) do
      {:ok, game, revision} ->
        play(game, revision, path, move)

      :not_found ->
        {:error, :game_not_found}
    end
  end

  @spec edit(Game.id(), Game.path(), PositionDraft.t()) ::
          {:ok, Game.t(), pos_integer(), Game.path()}
          | {:error,
             :game_not_found
             | :node_not_found
             | {:invalid_position, [atom()]}
             | :conflict
             | position_store_error()}
  def edit(game_id, path, %PositionDraft{} = draft) do
    case get(game_id) do
      {:ok, game, revision} ->
        edit(game, revision, path, draft)

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

  @spec promote(Game.id(), Game.path()) ::
          {:ok, Game.t(), pos_integer(), Game.path()}
          | {:error, :game_not_found | :node_not_found | :root | :conflict}
  def promote(game_id, path) do
    case get(game_id) do
      {:ok, game, revision} ->
        promote(game, revision, path)

      :not_found ->
        {:error, :game_not_found}
    end
  end

  @spec remove(Game.id(), Game.path()) ::
          {:ok, Game.t(), pos_integer(), Game.path()}
          | {:error, :game_not_found | :node_not_found | :root | :conflict}
  def remove(game_id, path) do
    case get(game_id) do
      {:ok, game, revision} ->
        remove(game, revision, path)

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

  defp play(
         game,
         revision,
         path,
         move
       ) do
    with %Node{} = node <-
           Game.node_at(
             game,
             path
           ),
         {:ok, position} <-
           get_position(Node.position_id(node)),
         {:ok, next_position} <-
           Position.apply_move(
             position,
             move
           ),
         {:ok, position_id} <-
           append_position(next_position) do
      transition =
        Transition.move(move)

      updated_game =
        Game.add_child(
          game,
          path,
          transition,
          position_id
        )

      child_index =
        updated_game
        |> Game.node_at(path)
        |> Node.child_index(
          transition,
          position_id
        )

      resulting_path =
        path ++ [child_index]

      case persist(
             updated_game,
             revision
           ) do
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

      {:error, {:position_store, _reason}} = error ->
        error
    end
  end

  defp promote(game, revision, path) do
    with {:ok, updated_game, resulting_path} <- Game.promote(game, path),
         {:ok, new_revision} <- persist(updated_game, revision) do
      {:ok, updated_game, new_revision, resulting_path}
    end
  end

  defp persist(game, revision) do
    case GameStore.update(game, revision) do
      {:ok, new_revision} ->
        :ok = GameEvents.publish_changed(game.id)
        {:ok, new_revision}

      {:error, :conflict} ->
        {:error, :conflict}

      {:error, :not_found} ->
        {:error, :game_not_found}
    end
  end

  defp remove(game, revision, path) do
    with {:ok, updated_game, resulting_path} <- Game.remove(game, path),
         {:ok, new_revision} <- persist(updated_game, revision) do
      {:ok, updated_game, new_revision, resulting_path}
    end
  end

  defp edit(
         game,
         revision,
         path,
         draft
       ) do
    with %Node{} <-
           Game.node_at(
             game,
             path
           ),
         {:ok, position} <-
           PositionDraft.apply(draft),
         {:ok, position_id} <-
           append_position(position) do
      transition =
        Transition.edit()

      updated_game =
        Game.add_child(
          game,
          path,
          transition,
          position_id
        )

      child_index =
        updated_game
        |> Game.node_at(path)
        |> Node.child_index(
          transition,
          position_id
        )

      resulting_path =
        path ++ [child_index]

      case persist(
             updated_game,
             revision
           ) do
        {:ok, new_revision} ->
          {:ok, updated_game, new_revision, resulting_path}

        {:error, _reason} = error ->
          error
      end
    else
      nil ->
        {:error, :node_not_found}

      {:error, {:position_store, _reason}} = error ->
        error

      {:error, reasons} ->
        {:error, {:invalid_position, reasons}}
    end
  end

  defp append_position(position) do
    case PositionStore.append(position) do
      position_id
      when is_integer(position_id) and
             position_id > 0 ->
        {:ok, position_id}

      {:error, reason} ->
        {:error, {:position_store, reason}}
    end
  end

  defp get_position(position_id) do
    case PositionStore.get(position_id) do
      {:ok, position} ->
        {:ok, position}

      :not_found ->
        :not_found

      {:error, reason} ->
        {:error, {:position_store, reason}}
    end
  end
end
