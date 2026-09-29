defmodule Web.AnalysisView do
  @moduledoc """
  Presentation data derived from rooms, analysis occurrences and positions.

  This belongs in `apps/web`: it formats domain data for HEEx without
  changing the ownership or representation of the analysis/chess models.
  """

  alias Analysis.Analysis, as: AnalysisModel
  alias Analysis.Analyses
  alias Analysis.Node
  alias Analysis.PositionStore
  alias Chess.Position
  alias Chess.PositionProperties

  @spec room_analyses(Analysis.Room.t(), String.t()) :: [map()]
  def room_analyses(room, locale) do
    room.analysis_ids
    |> Enum.with_index()
    |> Enum.flat_map(fn {id, index} ->
      case Analyses.get(id) do
        {:ok, analysis, revision} ->
          start_number =
            Analysis.GameStart.fullmove_number(analysis.start)

          source_game_record_id =
            AnalysisModel.source_game_record_id(analysis)

          label =
            if source_game_record_id do
              Web.I18n.t(
                "room.fromGame",
                locale,
                %{id: source_game_record_id}
              )
            else
              Web.I18n.t(
                "room.analysisLabel",
                locale,
                %{index: index + 1}
              )
            end

          start_label =
            if start_number > 1 do
              Web.I18n.t(
                "room.fromMove",
                locale,
                %{move: start_number}
              )
            else
              Web.I18n.t(
                "room.standardStart",
                locale
              )
            end

          [
            %{
              id: id,
              revision: revision,
              label: label,
              detail:
                start_label <>
                  " · " <>
                  Web.I18n.t(
                    "room.revision",
                    locale,
                    %{revision: revision}
                  ),
              source_game_record_id: source_game_record_id,
              start: analysis.start
            }
          ]

        :not_found ->
          []
      end
    end)
  end

  @spec fetch_analysis(String.t()) ::
          {:ok, AnalysisModel.t(), pos_integer()}
          | :not_found
  def fetch_analysis(analysis_id) do
    Analyses.get(analysis_id)
  end

  @spec current_position(AnalysisModel.t(), [non_neg_integer()]) ::
          {:ok, Node.t(), Position.t()} | :not_found
  def current_position(analysis, path) do
    with %Node{} = node <- AnalysisModel.node_at(analysis, path),
         {:ok, %Position{} = position} <- PositionStore.get(Node.position_id(node)) do
      {:ok, node, position}
    else
      _ -> :not_found
    end
  end

  @spec insights(Position.t()) :: map()
  def insights(%Position{} = position) do
    %{
      material: PositionProperties.material(position),
      space: PositionProperties.space(position),
      open_files: PositionProperties.open_files(position),
      semi_open_files: PositionProperties.semi_open_files(position),
      attacked_squares: PositionProperties.attacked_squares(position),
      attacked_pieces: PositionProperties.attacked_pieces(position),
      king_zone: %{
        white: PositionProperties.king_zone(position, :white),
        black: PositionProperties.king_zone(position, :black)
      },
      outposts: PositionProperties.outposts(position),
      in_check: PositionProperties.in_check(position),
      checkmate: %{
        white: Position.checkmate?(position, :white),
        black: Position.checkmate?(position, :black)
      }
    }
  end

  @spec checked_king_squares(Position.t()) :: [0..63]
  def checked_king_squares(position) do
    for {square, {color, :king}} <- Position.pieces(position),
        Position.in_check?(position, color),
        do: square
  end

  @spec move_entries(AnalysisModel.t(), String.t()) :: [map()]
  def move_entries(%AnalysisModel{} = analysis, locale) do
    move_list_data(analysis, locale).entries
  end

  @doc "Builds the paired mainline rows and recursive variation rows used by the move tree."
  @spec move_list_data(AnalysisModel.t(), String.t()) :: %{
          entries: [map()],
          focus_paths: [[non_neg_integer()]],
          rows: [map()]
        }
  def move_list_data(%AnalysisModel{} = analysis, locale) do
    root = AnalysisModel.root(analysis)

    case position_for(root) do
      %Position{} = root_position ->
        tree =
          collect_move_tree(
            Node.children(root),
            [],
            root_position,
            analysis,
            root_position.side_to_move,
            locale
          )

        rows = mainline_rows(tree, Enum.drop(tree, 1))

        %{
          entries: flatten_move_tree(tree),
          focus_paths: move_focus_paths(rows),
          rows: rows
        }

      _ ->
        %{entries: [], focus_paths: [], rows: []}
    end
  end

  @spec mainline_path(Node.t()) :: [non_neg_integer()]
  def mainline_path(root), do: mainline_path(root, [])

  @doc "Returns leaf paths for occurrences newly appended to an analysis tree."
  @spec newly_added_paths(AnalysisModel.t(), AnalysisModel.t()) :: [Analysis.Analysis.path()]
  def newly_added_paths(%AnalysisModel{} = old_analysis, %AnalysisModel{} = new_analysis) do
    compare_nodes(AnalysisModel.root(old_analysis), AnalysisModel.root(new_analysis), [])
  end

  defp mainline_path(%Node{children: []}, path), do: path

  defp mainline_path(%Node{children: [_child | _]} = node, path) do
    node
    |> Node.children()
    |> hd()
    |> mainline_path(path ++ [0])
  end

  defp compare_nodes(old_node, new_node, parent_path) do
    old_children = Node.children(old_node)

    new_node
    |> Node.children()
    |> Enum.with_index()
    |> Enum.flat_map(fn {new_child, index} ->
      case Enum.find_index(old_children, &same_occurrence?(&1, new_child)) do
        nil ->
          [mainline_leaf(new_child, parent_path ++ [index])]

        ^index ->
          compare_nodes(Enum.at(old_children, index), new_child, parent_path ++ [index])

        _other_index ->
          []
      end
    end)
  end

  defp same_occurrence?(%Node{} = left, %Node{} = right) do
    Node.position_id(left) == Node.position_id(right) and
      Node.transition(left) == Node.transition(right)
  end

  defp mainline_leaf(%Node{children: []}, path), do: path
  defp mainline_leaf(%Node{children: [child | _]}, path), do: mainline_leaf(child, path ++ [0])

  defp collect_move_tree(children, parent_path, parent_position, analysis, root_side, locale) do
    children
    |> Enum.with_index()
    |> Enum.map(fn {node, index} ->
      path = parent_path ++ [index]
      context = AnalysisModel.move_context(analysis, root_side, parent_path)
      transition = Node.transition(node)
      label = transition_label(transition, parent_position, locale)
      child_position = position_for(node)

      entry = %{
        path: path,
        label: label,
        prefix: move_prefix(context),
        depth: Enum.count(path, &(&1 > 0)),
        edit?: transition == :edit,
        comment: Node.comment(node),
        nags: Enum.take(Node.nags(node), 1),
        side: context.side,
        children: []
      }

      case child_position do
        %Position{} = child_position ->
          Map.put(
            entry,
            :children,
            collect_move_tree(
              Node.children(node),
              path,
              child_position,
              analysis,
              root_side,
              locale
            )
          )

        _ ->
          entry
      end
    end)
  end

  defp flatten_move_tree(entries) do
    Enum.flat_map(entries, fn entry ->
      [Map.delete(entry, :children) | flatten_move_tree(entry.children)]
    end)
  end

  defp mainline_rows([], _root_variations), do: []

  defp mainline_rows([mainline | _other_root_moves], root_variations) do
    {moves, next_mainline, variations} = mainline_row(mainline)

    row = %{type: :mainline, moves: moves}
    variation_rows = Enum.map(root_variations ++ variations, &%{type: :variation, root: &1})
    next_rows = if next_mainline, do: mainline_rows([next_mainline], []), else: []

    [row | variation_rows] ++ next_rows
  end

  defp mainline_row(%{side: :white} = entry) do
    case entry.children do
      [black_reply | other_replies] when black_reply.side == :black ->
        moves = [
          %{entry: without_children(entry), show_number: true},
          %{entry: without_children(black_reply), show_number: false}
        ]

        {moves, List.first(black_reply.children),
         other_replies ++ Enum.drop(black_reply.children, 1)}

      children ->
        {[%{entry: without_children(entry), show_number: true}], List.first(children),
         Enum.drop(children, 1)}
    end
  end

  defp mainline_row(%{side: :black} = entry) do
    {[%{entry: without_children(entry), show_number: true}], List.first(entry.children),
     Enum.drop(entry.children, 1)}
  end

  defp without_children(entry), do: Map.delete(entry, :children)

  defp move_focus_paths(rows), do: Enum.flat_map(rows, &move_row_focus_paths/1)

  defp move_row_focus_paths(%{type: :mainline, moves: moves}),
    do: Enum.map(moves, & &1.entry.path)

  defp move_row_focus_paths(%{type: :variation, root: root}), do: variation_focus_paths(root)

  defp variation_focus_paths(entry) do
    children = entry.children
    nested = Enum.drop(children, 1) |> Enum.flat_map(&variation_focus_paths/1)

    mainline =
      case children do
        [child | _] -> variation_focus_paths(child)
        [] -> []
      end

    [entry.path | nested ++ mainline]
  end

  defp position_for(%Node{} = node) do
    case PositionStore.get(Node.position_id(node)) do
      {:ok, %Position{} = position} -> position
      _ -> nil
    end
  end

  defp transition_label({:move, _move} = transition, parent_position, locale) do
    case Web.ChessNotation.format(parent_position, transition, locale) do
      {:ok, san} -> san
      _ -> "?"
    end
  end

  defp transition_label(:edit, _parent_position, locale),
    do: Web.I18n.t("room.editTransition", locale)

  defp transition_label(_transition, _parent_position, _locale), do: ""

  defp move_prefix(%Analysis.MoveContext{fullmove_number: number, side: :white}), do: "#{number}."

  defp move_prefix(%Analysis.MoveContext{fullmove_number: number, side: :black}),
    do: "#{number}..."
end
