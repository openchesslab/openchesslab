defmodule Web.PersonalAnalysisLive do
  use Web, :live_view

  import Web.ChessComponents

  alias Analysis.Analysis, as: AnalysisModel
  alias Analysis.Node
  alias Analysis.UserLibrary
  alias Chess.Position
  alias Web.AnalysisView

  @impl true
  def mount(_params, session, socket) do
    locale = Web.I18n.locale_from_session(session)

    socket =
      socket
      |> assign(
        locale: locale,
        page_title: Web.I18n.t("personal.title", locale),
        analysis: nil,
        current_path: [],
        orientation: "white",
        selected_square: nil,
        legal_targets: [],
        cursor_square: nil,
        pending_promotion: nil,
        notice: nil
      )
      |> attach_hook(:private_access, :handle_event, fn _, _, socket ->
        case UserLibrary.get_private(socket.assigns.current_user.id, socket.assigns.analysis.id) do
          {:ok, _, _} -> {:cont, socket}
          :not_found -> {:halt, unavailable(socket)}
        end
      end)

    {:ok, socket, layout: false}
  end

  @impl true
  def handle_params(%{"id" => id} = params, _uri, socket) do
    case UserLibrary.get_private(socket.assigns.current_user.id, id) do
      {:ok, analysis, revision} ->
        notice = socket.assigns.notice

        {:noreply,
         socket |> display(analysis, revision, parse_path(params["p"])) |> assign(:notice, notice)}

      :not_found ->
        {:noreply, unavailable(socket)}
    end
  end

  @impl true
  def handle_event("select-path", %{"path" => path}, socket),
    do: {:noreply, navigate_path(socket, parse_path(path))}

  def handle_event("move-tree-key", %{"path" => path, "key" => key}, socket) do
    path = parse_path(path)

    target =
      case key do
        "ArrowLeft" -> Enum.drop(path, -1)
        "ArrowRight" -> path ++ [0]
        "ArrowUp" -> sibling(path, -1)
        "ArrowDown" -> sibling(path, 1)
        _ -> path
      end

    {:noreply, navigate_path(socket, target)}
  end

  def handle_event("first-move", _, socket), do: {:noreply, navigate_path(socket, [])}

  def handle_event("toggle-orientation", _, socket),
    do:
      {:noreply,
       assign(
         socket,
         :orientation,
         if(socket.assigns.orientation == "white", do: "black", else: "white")
       )}

  def handle_event("board-cursor", %{"square" => square}, socket) do
    {:noreply, assign(socket, :cursor_square, square(square))}
  end

  def handle_event("board-square", %{"square" => value}, socket) do
    target = square(value)
    position = socket.assigns.position
    selected = socket.assigns.selected_square

    cond do
      is_nil(target) ->
        {:noreply, socket}

      target in socket.assigns.legal_targets ->
        play(socket, selected, target, nil)

      match?({side, _} when side == position.side_to_move, Position.piece_at(position, target)) ->
        targets =
          position
          |> Position.legal_moves()
          |> Enum.filter(&(&1.from == target))
          |> Enum.map(& &1.to)

        {:noreply, assign(socket, selected_square: target, legal_targets: targets)}

      true ->
        {:noreply, assign(socket, selected_square: nil, legal_targets: [])}
    end
  end

  def handle_event("board-move", %{"from" => from, "to" => to}, socket),
    do: play(socket, square(from), square(to), nil)

  def handle_event("promote-pawn", %{"promotion" => promotion}, socket) do
    case {socket.assigns.pending_promotion, promotion_kind(promotion)} do
      {{from, to}, kind} when not is_nil(kind) -> play(socket, from, to, kind)
      _ -> {:noreply, socket}
    end
  end

  def handle_event("save-comment", %{"comment" => text}, socket),
    do: edit(socket, {:comment, text})

  def handle_event("promote-variation", _, socket), do: edit(socket, :promote)
  def handle_event("remove-subtree", _, socket), do: edit(socket, :remove)

  def handle_event("toggle-nag", %{"nag" => value}, socket) when value in ~w(1 2 3 4 5 6) do
    nag = String.to_integer(value)
    nags = if nag in Node.nags(socket.assigns.node), do: [], else: [nag]
    edit(socket, {:nags, nags})
  end

  def handle_event(_, _, socket), do: {:noreply, socket}

  defp play(socket, from, to, promotion) do
    moves =
      socket.assigns.position
      |> Position.legal_moves()
      |> Enum.filter(&(&1.from == from and &1.to == to))

    cond do
      moves == [] ->
        {:noreply,
         assign(socket,
           notice: Web.I18n.t("room.illegalMove", socket.assigns.locale),
           selected_square: nil,
           legal_targets: []
         )}

      is_nil(promotion) and Enum.any?(moves, & &1.promotion) ->
        {:noreply, assign(socket, :pending_promotion, {from, to})}

      true ->
        move = Enum.find(moves, &(&1.promotion == promotion))
        if move, do: edit(socket, {:play, move}), else: {:noreply, socket}
    end
  end

  defp edit(socket, command) do
    assigns = socket.assigns

    case UserLibrary.edit_private(
           assigns.current_user.id,
           assigns.analysis.id,
           assigns.revision,
           assigns.current_path,
           command
         ) do
      {:ok, analysis, revision, path} ->
        {:noreply, socket |> display(analysis, revision, path) |> patch_path()}

      {:ok, analysis, revision} ->
        {:noreply, display(socket, analysis, revision, assigns.current_path)}

      {:error, :analysis_not_found} ->
        {:noreply, unavailable(socket)}

      {:error, :conflict} ->
        case UserLibrary.get_private(assigns.current_user.id, assigns.analysis.id) do
          {:ok, analysis, revision} ->
            path = AnalysisModel.reconcile_path(assigns.analysis, analysis, assigns.current_path)

            {:noreply,
             socket
             |> display(analysis, revision, path)
             |> assign(:notice, Web.I18n.t("personal.conflict", assigns.locale))
             |> patch_path()}

          :not_found ->
            {:noreply, unavailable(socket)}
        end

      {:error, _} ->
        {:noreply, assign(socket, :notice, Web.I18n.t("personal.editFailed", assigns.locale))}
    end
  end

  defp display(socket, analysis, revision, path) do
    path = if AnalysisModel.node_at(analysis, path), do: path, else: []
    node = AnalysisModel.node_at(analysis, path)
    {:ok, position} = Analysis.PositionStore.get(Node.position_id(node))
    data = AnalysisView.move_list_data(analysis, socket.assigns.locale)

    assign(socket,
      analysis: analysis,
      revision: revision,
      current_path: path,
      node: node,
      position: position,
      move_rows: data.rows,
      move_entries: data.entries,
      selected_square: nil,
      legal_targets: [],
      pending_promotion: nil,
      notice: nil
    )
  end

  defp navigate_path(socket, path) do
    if AnalysisModel.node_at(socket.assigns.analysis, path) do
      socket |> display(socket.assigns.analysis, socket.assigns.revision, path) |> patch_path()
    else
      socket
    end
  end

  defp patch_path(socket) do
    path = Enum.join(socket.assigns.current_path, ",")
    url = ~p"/library/#{socket.assigns.analysis.id}"
    push_patch(socket, to: if(path == "", do: url, else: url <> "?p=" <> path), replace: true)
  end

  defp unavailable(socket),
    do:
      socket
      |> put_flash(:error, Web.I18n.t("personal.unavailable", socket.assigns.locale))
      |> redirect(to: "/library")

  defp sibling([], _), do: []
  defp sibling(path, delta), do: Enum.drop(path, -1) ++ [max(0, List.last(path) + delta)]

  defp parse_path(path) when is_binary(path) do
    parts = String.split(path, ",", trim: true)

    if length(parts) <= 512 and Enum.all?(parts, &match?({n, ""} when n >= 0, Integer.parse(&1))),
      do: Enum.map(parts, &String.to_integer/1),
      else: []
  end

  defp parse_path(_), do: []
  defp square(n) when is_integer(n) and n in 0..63, do: n

  defp square(n) when is_binary(n) do
    case Integer.parse(n) do
      {n, ""} when n in 0..63 -> n
      _ -> nil
    end
  end

  defp square(_), do: nil
  defp promotion_kind("queen"), do: :queen
  defp promotion_kind("rook"), do: :rook
  defp promotion_kind("bishop"), do: :bishop
  defp promotion_kind("knight"), do: :knight
  defp promotion_kind(_), do: nil
end
