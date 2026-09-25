defmodule Analysis do
  alias Analysis.Node
  alias Analysis.Transition
  alias Chess.Move
  alias Chess.Position
  alias Chess.PositionDraft

  @spec play(
          Analysis.Analysis.t(),
          PositionDB.t(),
          Analysis.Analysis.path(),
          Move.t()
        ) ::
          {:ok, Analysis.Analysis.t(), PositionDB.t(), Analysis.Analysis.path()}
          | {:error, :node_not_found | :position_not_found | :illegal_move}
  def play(analysis, db, path, move) do
    with %Node{} = node <- Analysis.Analysis.node_at(analysis, path),
         {:ok, position} <- PositionDB.get(db, Node.position_id(node)),
         {:ok, next_position} <- Position.apply_move(position, move) do
      {db, position_id} = PositionDB.append(db, next_position)
      transition = Transition.move(move)

      analysis =
        Analysis.Analysis.add_child(
          analysis,
          path,
          transition,
          position_id
        )

      child_index =
        analysis
        |> Analysis.Analysis.node_at(path)
        |> Node.child_index(transition, position_id)

      {:ok, analysis, db, path ++ [child_index]}
    else
      nil ->
        {:error, :node_not_found}

      :not_found ->
        {:error, :position_not_found}

      {:error, :illegal_move} = error ->
        error
    end
  end

  @spec edit(
          Analysis.Analysis.t(),
          PositionDB.t(),
          Analysis.Analysis.path(),
          PositionDraft.t()
        ) ::
          {:ok, Analysis.Analysis.t(), PositionDB.t(), Analysis.Analysis.path()}
          | {:error,
             :node_not_found
             | {:invalid_position, [atom()]}}
  def edit(analysis, db, path, %PositionDraft{} = draft) do
    with %Node{} <- Analysis.Analysis.node_at(analysis, path),
         {:ok, position} <- PositionDraft.apply(draft) do
      {db, position_id} = PositionDB.append(db, position)
      transition = Transition.edit()

      analysis =
        Analysis.Analysis.add_child(
          analysis,
          path,
          transition,
          position_id
        )

      child_index =
        analysis
        |> Analysis.Analysis.node_at(path)
        |> Node.child_index(transition, position_id)

      {:ok, analysis, db, path ++ [child_index]}
    else
      nil ->
        {:error, :node_not_found}

      {:error, reasons} ->
        {:error, {:invalid_position, reasons}}
    end
  end
end
