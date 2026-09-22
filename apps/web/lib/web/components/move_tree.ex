defmodule Web.Components.MoveTree do
  use Phoenix.Component

  alias Analysis.Game
  alias Analysis.MoveContext
  alias Analysis.Node
  alias Analysis.PositionStore
  alias Analysis.TransitionNotation

  attr(:game, :any, required: true)
  attr(:root_position, :any, required: true)

  def move_tree(assigns) do
    assigns =
      assigns
      |> assign(:root, Game.root(assigns.game))
      |> assign(:root_side, assigns.root_position.side_to_move)

    ~H"""
    <div id="move-tree">
      <div id="move-tree-main">
        <.continuation
          game={@game}
          node={@root}
          position={@root_position}
          root_side={@root_side}
          path={[]}
        />
      </div>
    </div>
    """
  end

  attr(:game, :any, required: true)
  attr(:node, :any, required: true)
  attr(:position, :any, required: true)
  attr(:root_side, :atom, required: true)
  attr(:path, :list, required: true)

  defp continuation(assigns) do
    children = Node.children(assigns.node)

    assigns =
      assigns
      |> assign(:main_child, List.first(children))
      |> assign(:variations, children |> Enum.drop(1) |> Enum.with_index(1))

    ~H"""
    <%= if @main_child do %>
      <.move
        game={@game}
        child={@main_child}
        position={@position}
        root_side={@root_side}
        parent_path={@path}
        child_index={0}
      />

      <div
        :for={{child, child_index} <- @variations}
        id={"move-tree-variation-#{path_id(@path ++ [child_index])}"}
        class="move-tree-variation"
      >
        <.move
          game={@game}
          child={child}
          position={@position}
          root_side={@root_side}
          parent_path={@path}
          child_index={child_index}
        />
      </div>
    <% end %>
    """
  end

  attr(:game, :any, required: true)
  attr(:child, :any, required: true)
  attr(:position, :any, required: true)
  attr(:root_side, :atom, required: true)
  attr(:parent_path, :list, required: true)
  attr(:child_index, :integer, required: true)

  defp move(assigns) do
    path = assigns.parent_path ++ [assigns.child_index]

    context =
      Game.move_context(
        assigns.game,
        assigns.root_side,
        assigns.parent_path
      )

    notation =
      transition_label(
        assigns.position,
        Node.transition(assigns.child)
      )

    child_position =
      case PositionStore.get(Node.position_id(assigns.child)) do
        {:ok, position} -> position
        :not_found -> nil
      end

    assigns =
      assigns
      |> assign(:path, path)
      |> assign(:context, context)
      |> assign(:notation, notation)
      |> assign(:child_position, child_position)

    ~H"""
    <button
      id={"move-tree-#{path_id(@path)}"}
      type="button"
      phx-click="navigate_path"
      phx-value-path={encode_path(@path)}
    >
      <span>{move_number_label(@context)}</span> {@notation}
    </button>

    <.continuation
      :if={@child_position}
      game={@game}
      node={@child}
      position={@child_position}
      root_side={@root_side}
      path={@path}
    />
    """
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
