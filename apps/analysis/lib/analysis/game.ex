defmodule Analysis.Game do
  alias Analysis.Node

  @type id :: term()
  @type path :: [non_neg_integer()]
  @type position_id :: term()

  @type t :: %__MODULE__{
          id: id(),
          root: Node.t(),
          metadata: map()
        }

  @enforce_keys [:id, :root]
  defstruct id: nil, root: nil, metadata: %{}

  @spec new(id(), position_id()) :: t()
  def new(id, initial_position_id) do
    %__MODULE__{
      id: id,
      root: Node.new(initial_position_id)
    }
  end

  @spec new(id(), position_id(), map()) :: t()
  def new(id, initial_position_id, metadata) when is_map(metadata) do
    %__MODULE__{
      id: id,
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

  @spec reconcile_path(t(), t(), path()) :: path()
  def reconcile_path(%__MODULE__{} = old_game, %__MODULE__{} = new_game, path)
      when is_list(path) do
    old_nodes =
      path
      |> prefixes()
      |> Enum.map(&node_at(old_game, &1))

    new_root = root(new_game)

    follow_occurrences(new_root, tl(old_nodes), [])
  end

  @spec add_child(t(), path(), Analysis.Transition.t(), position_id()) :: t()
  def add_child(%__MODULE__{} = game, path, transition, position_id)
      when is_list(path) do
    case add_child_at(game.root, path, transition, position_id) do
      {:ok, root} ->
        %{game | root: root}

      :not_found ->
        game
    end
  end

  @spec promote(t(), path()) ::
          {:ok, t(), path()}
          | {:error, :node_not_found | :root}
  def promote(%__MODULE__{}, []) do
    {:error, :root}
  end

  def promote(%__MODULE__{} = game, path) when is_list(path) do
    {parent_path, [child_index]} = Enum.split(path, -1)

    case promote_child_at(game.root, parent_path, child_index) do
      {:ok, root} ->
        {:ok, %{game | root: root}, parent_path ++ [0]}

      :not_found ->
        {:error, :node_not_found}
    end
  end

  @spec remove(t(), path()) ::
          {:ok, t(), path()}
          | {:error, :node_not_found | :root}
  def remove(%__MODULE__{}, []) do
    {:error, :root}
  end

  def remove(%__MODULE__{} = game, path) when is_list(path) do
    {parent_path, [child_index]} = Enum.split(path, -1)

    case remove_child_at(game.root, parent_path, child_index) do
      {:ok, root} ->
        {:ok, %{game | root: root}, parent_path}

      :not_found ->
        {:error, :node_not_found}
    end
  end

  @spec set_comment(t(), path(), String.t() | nil) ::
          {:ok, t()}
          | {:error, :node_not_found}
  def set_comment(%__MODULE__{} = game, path, comment)
      when is_list(path) and (is_binary(comment) or is_nil(comment)) do
    comment = normalize_comment(comment)

    case update_node_at(game.root, path, fn node ->
           %{node | comment: comment}
         end) do
      {:ok, root} ->
        {:ok, %{game | root: root}}

      :not_found ->
        {:error, :node_not_found}
    end
  end

  defp add_child_at(node, [], transition, position_id) do
    if Enum.any?(Node.children(node), fn child ->
         Node.transition(child) == transition and
           Node.position_id(child) == position_id
       end) do
      {:ok, node}
    else
      child = Node.new(position_id, transition)
      {:ok, %{node | children: Node.children(node) ++ [child]}}
    end
  end

  defp add_child_at(node, [index | rest], transition, position_id)
       when is_integer(index) and index >= 0 do
    case Enum.fetch(Node.children(node), index) do
      {:ok, child} ->
        case add_child_at(child, rest, transition, position_id) do
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

  defp add_child_at(_node, _path, _transition, _position_id),
    do: :not_found

  defp find_node(node, []), do: node

  defp find_node(node, [index | rest])
       when is_integer(index) and index >= 0 do
    case Enum.at(Node.children(node), index) do
      nil -> nil
      child -> find_node(child, rest)
    end
  end

  defp find_node(_node, _path), do: nil

  defp promote_child_at(node, [], child_index)
       when is_integer(child_index) and child_index >= 0 do
    case Enum.fetch(Node.children(node), child_index) do
      {:ok, child} ->
        children =
          Node.children(node)
          |> List.delete_at(child_index)
          |> List.insert_at(0, child)

        {:ok, %{node | children: children}}

      :error ->
        :not_found
    end
  end

  defp promote_child_at(node, [index | rest], child_index)
       when is_integer(index) and index >= 0 do
    case Enum.fetch(Node.children(node), index) do
      {:ok, child} ->
        case promote_child_at(child, rest, child_index) do
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

  defp promote_child_at(_node, _path, _child_index), do: :not_found

  defp remove_child_at(node, [], child_index)
       when is_integer(child_index) and child_index >= 0 do
    case Enum.fetch(Node.children(node), child_index) do
      {:ok, _child} ->
        children = List.delete_at(Node.children(node), child_index)

        {:ok, %{node | children: children}}

      :error ->
        :not_found
    end
  end

  defp remove_child_at(node, [index | rest], child_index)
       when is_integer(index) and index >= 0 do
    case Enum.fetch(Node.children(node), index) do
      {:ok, child} ->
        case remove_child_at(child, rest, child_index) do
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

  defp remove_child_at(_node, _path, _child_index), do: :not_found

  defp normalize_comment(""), do: nil
  defp normalize_comment(comment), do: comment

  defp update_node_at(node, [], update) do
    {:ok, update.(node)}
  end

  defp update_node_at(node, [index | rest], update)
       when is_integer(index) and index >= 0 do
    case Enum.fetch(Node.children(node), index) do
      {:ok, child} ->
        case update_node_at(child, rest, update) do
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

  defp update_node_at(_node, _path, _update), do: :not_found

  defp follow_occurrences(_new_node, [], path), do: path

  defp follow_occurrences(new_node, [old_child | old_rest], path) do
    case matching_child(new_node, old_child) do
      nil ->
        path

      {child, index} ->
        follow_occurrences(child, old_rest, path ++ [index])
    end
  end

  defp matching_child(new_node, old_child) do
    new_node
    |> Node.children()
    |> Enum.with_index()
    |> Enum.find(fn {child, _index} ->
      same_occurrence?(old_child, child)
    end)
  end

  defp same_occurrence?(%Node{} = old_node, %Node{} = new_node) do
    Node.position_id(old_node) == Node.position_id(new_node) and
      Node.transition(old_node) == Node.transition(new_node)
  end

  defp same_occurrence?(_old_node, _new_node), do: false

  defp prefixes(path) do
    0..length(path)
    |> Enum.map(&Enum.take(path, &1))
  end
end
