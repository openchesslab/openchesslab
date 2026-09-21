defmodule Analysis.Game do
  alias Analysis.Node

  @type path :: [non_neg_integer()]
  @type position_id :: term()

  @type t :: %__MODULE__{
          root: Node.t(),
          metadata: map()
        }

  @enforce_keys [:root]
  defstruct root: nil, metadata: %{}

  @spec new(position_id()) :: t()
  def new(initial_position_id) do
    %__MODULE__{root: Node.new(initial_position_id)}
  end

  @spec new(position_id(), map()) :: t()
  def new(initial_position_id, metadata) when is_map(metadata) do
    %__MODULE__{
      root: Node.new(initial_position_id),
      metadata: metadata
    }
  end

  @spec root(t()) :: Node.t()
  def root(%__MODULE__{root: root}), do: root

  @spec node_at(t(), path()) :: Node.t() | nil
  def node_at(%__MODULE__{root: root}, path) when is_list(path) do
    find_node(root, path)
  end

  @spec add_child(t(), path(), Chess.Move.t(), position_id()) :: t()
  def add_child(%__MODULE__{} = game, path, move, position_id)
      when is_list(path) do
    case add_child_at(game.root, path, move, position_id) do
      {:ok, root} ->
        %{game | root: root}

      :not_found ->
        game
    end
  end

  defp add_child_at(node, [], move, position_id) do
    if Enum.any?(Node.children(node), &(Node.move(&1) == move)) do
      {:ok, node}
    else
      child = Node.new(position_id, move)
      {:ok, %{node | children: Node.children(node) ++ [child]}}
    end
  end

  defp add_child_at(node, [index | rest], move, position_id)
       when is_integer(index) and index >= 0 do
    case Enum.fetch(Node.children(node), index) do
      {:ok, child} ->
        case add_child_at(child, rest, move, position_id) do
          {:ok, updated_child} ->
            children =
              List.replace_at(
                Node.children(node),
                index,
                updated_child
              )

            {:ok, %{node | children: children}}

          :not_found ->
            :not_found
        end

      :error ->
        :not_found
    end
  end

  defp add_child_at(_node, _path, _move, _position_id), do: :not_found

  defp find_node(node, []), do: node

  defp find_node(node, [index | rest])
       when is_integer(index) and index >= 0 do
    case Enum.at(Node.children(node), index) do
      nil -> nil
      child -> find_node(child, rest)
    end
  end

  defp find_node(_node, _path), do: nil
end
