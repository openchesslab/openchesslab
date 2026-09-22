defmodule Analysis do
  alias Analysis.Game
  alias Analysis.Node
  alias Analysis.Transition
  alias Chess.Move
  alias Chess.Position

  @spec play(
          Game.t(),
          PositionDB.t(),
          Game.path(),
          Move.t()
        ) ::
          {:ok, Game.t(), PositionDB.t(), Game.path()}
          | {:error, :node_not_found | :position_not_found | :illegal_move}
  def play(game, db, path, move) do
    with %Node{} = node <- Game.node_at(game, path),
         {:ok, position} <- PositionDB.get(db, Node.position_id(node)),
         {:ok, next_position} <- Position.apply_move(position, move) do
      {db, position_id} = PositionDB.append(db, next_position)
      transition = Transition.move(move)

      game =
        Game.add_child(
          game,
          path,
          transition,
          position_id
        )

      child_index =
        game
        |> Game.node_at(path)
        |> Node.child_index(transition, position_id)

      {:ok, game, db, path ++ [child_index]}
    else
      nil ->
        {:error, :node_not_found}

      :not_found ->
        {:error, :position_not_found}

      {:error, :illegal_move} = error ->
        error
    end
  end
end
