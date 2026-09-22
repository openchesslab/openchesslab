defmodule Web.Components.MoveTree do
  use Phoenix.Component

  alias Analysis.Game
  alias Analysis.MoveContext
  alias Analysis.Node
  alias Analysis.TransitionNotation

  attr(:game, :any, required: true)
  attr(:root_position, :any, required: true)

  def move_tree(assigns) do
    moves =
      main_line(
        assigns.game,
        assigns.root_position
      )

    assigns = assign(assigns, :moves, moves)

    ~H"""
    <div id="move-tree">
      <button
        :for={move <- @moves}
        id={"move-tree-#{path_id(move.path)}"}
        type="button"
        phx-click="navigate_path"
        phx-value-path={encode_path(move.path)}
      >
        <span>{move_number_label(move.context)}</span> {move.notation}
      </button>
    </div>
    """
  end

  defp main_line(game, root_position) do
    collect_main_line(
      game,
      Game.root(game),
      root_position,
      root_position.side_to_move,
      [],
      []
    )
  end

  defp collect_main_line(
         game,
         node,
         position,
         root_side,
         path,
         moves
       ) do
    case Node.main_child(node) do
      nil ->
        Enum.reverse(moves)

      child ->
        child_path = path ++ [0]

        context =
          Game.move_context(
            game,
            root_side,
            path
          )

        move = %{
          path: child_path,
          context: context,
          notation:
            transition_label(
              position,
              Node.transition(child)
            )
        }

        case Analysis.PositionStore.get(Node.position_id(child)) do
          {:ok, child_position} ->
            collect_main_line(
              game,
              child,
              child_position,
              root_side,
              child_path,
              [move | moves]
            )

          :not_found ->
            Enum.reverse([move | moves])
        end
    end
  end

  defp transition_label(position, transition) do
    case TransitionNotation.format(position, transition) do
      {:ok, notation} -> notation
      :not_applicable -> "Edited position"
      {:error, :illegal_move} -> "Invalid move"
    end
  end

  defp move_number_label(%MoveContext{
         fullmove_number: number,
         side: :white
       }) do
    "#{number}."
  end

  defp move_number_label(%MoveContext{
         fullmove_number: number,
         side: :black
       }) do
    "#{number}..."
  end

  defp path_id(path), do: Enum.join(path, "-")
  defp encode_path(path), do: Enum.join(path, ",")
end
