defmodule Web.RoomLive do
  use Web, :live_view

  alias Analysis.AnalysisEvents
  alias Analysis.Analyses
  alias Analysis.Node
  alias Analysis.PositionStore
  alias Analysis.RoomEvents
  alias Analysis.Rooms
  alias Chess.Move
  alias Chess.PositionDraft
  alias Chess.Square
  alias Web.ChessNotation
  alias Web.Components.ChessBoard
  alias Web.Components.MoveTree
  alias Web.Components.PositionEditor

  @impl true
  def mount(%{"room_id" => room_id} = params, _session, socket) do
    {:ok, room} = Rooms.start_room(room_id)

    if connected?(socket) do
      :ok = RoomEvents.subscribe(room_id)
    end

    socket =
      assign(socket,
        room_id: room_id,
        room: room,
        add_analysis_error: nil,
        move_error: nil,
        edit_error: nil,
        position_error: nil,
        selected_analysis_id: nil,
        analysis: nil,
        analysis_revision: nil,
        current_path: [],
        selected_square: nil,
        root_position: nil,
        position: nil,
        create_analysis_error: nil
      )

    socket =
      case Map.get(params, "analysis_id") do
        nil ->
          socket

        analysis_id ->
          select_analysis(socket, analysis_id)
      end

    {:ok, socket}
  end

  @impl true
  def handle_info({:room_changed, room_id}, %{assigns: %{room_id: room_id}} = socket) do
    case Rooms.get(room_id) do
      {:ok, room} ->
        {:noreply, assign(socket, :room, room)}

      :not_found ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info(
        {:analysis_changed, analysis_id},
        %{assigns: %{selected_analysis_id: analysis_id}} = socket
      ) do
    case Analyses.get(analysis_id) do
      {:ok, analysis, revision} ->
        current_path =
          Analysis.Analysis.reconcile_path(
            socket.assigns.analysis,
            analysis,
            socket.assigns.current_path
          )

        socket =
          socket
          |> assign(:analysis_revision, revision)
          |> assign_current_occurrence(analysis, current_path)

        {:noreply, socket}

      :not_found ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "add_analysis",
        %{"analysis" => %{"id" => analysis_id}},
        socket
      ) do
    case Analyses.get(analysis_id) do
      {:ok, _analysis, _revision} ->
        :ok = Rooms.add_analysis(socket.assigns.room_id, analysis_id)

        {:noreply, assign(socket, :add_analysis_error, nil)}

      :not_found ->
        {:noreply, assign(socket, :add_analysis_error, gettext("Analysis not found."))}
    end
  end

  @impl true
  def handle_event(
        "remove_analysis",
        %{"analysis_id" => analysis_id},
        socket
      ) do
    :ok = Rooms.remove_analysis(socket.assigns.room_id, analysis_id)

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "select_analysis",
        %{"analysis_id" => analysis_id},
        socket
      ) do
    {:noreply, select_analysis(socket, analysis_id)}
  end

  @impl true
  def handle_event(
        "navigate_child",
        %{"index" => index},
        %{assigns: %{analysis: analysis, current_path: path}} = socket
      ) do
    child_index = String.to_integer(index)
    new_path = path ++ [child_index]

    if Analysis.Analysis.node_at(analysis, new_path) do
      {:noreply, assign_current_occurrence(socket, analysis, new_path)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "navigate_parent",
        _params,
        %{assigns: %{current_path: []}} = socket
      ) do
    {:noreply, socket}
  end

  def handle_event(
        "navigate_parent",
        _params,
        %{assigns: %{current_path: path}} = socket
      ) do
    new_path = Enum.drop(path, -1)

    {:noreply,
     assign_current_occurrence(
       socket,
       socket.assigns.analysis,
       new_path
     )}
  end

  @impl true
  def handle_event(
        "play_move",
        %{"move" => %{"from" => from, "to" => to}},
        socket
      ) do
    with from_square when is_integer(from_square) <-
           Square.from_algebraic(from),
         to_square when is_integer(to_square) <-
           Square.from_algebraic(to) do
      move = Move.new(from_square, to_square)

      play_move(socket, move)
    else
      {:error, :invalid_square} ->
        {:noreply, assign(socket, :move_error, gettext("Invalid square."))}
    end
  end

  @impl true
  def handle_event(
        "square_clicked",
        %{"square" => square},
        %{assigns: %{selected_square: nil}} = socket
      ) do
    case Square.from_algebraic(square) do
      selected_square when is_integer(selected_square) ->
        {:noreply, assign(socket, :selected_square, selected_square)}

      {:error, :invalid_square} ->
        {:noreply, socket}
    end
  end

  def handle_event(
        "square_clicked",
        %{"square" => square},
        %{assigns: %{selected_square: from_square}} = socket
      ) do
    case Square.from_algebraic(square) do
      to_square when is_integer(to_square) ->
        socket = assign(socket, :selected_square, nil)
        move = Move.new(from_square, to_square)

        play_move(socket, move)

      {:error, :invalid_square} ->
        {:noreply, assign(socket, :selected_square, nil)}
    end
  end

  @impl true
  def handle_event(
        "remove_piece",
        %{"edit" => %{"square" => square}},
        socket
      ) do
    case Square.from_algebraic(square) do
      square when is_integer(square) ->
        draft =
          socket.assigns.position
          |> PositionDraft.new()
          |> PositionDraft.remove_piece(square)

        edit_position(socket, draft)

      {:error, :invalid_square} ->
        {:noreply, assign(socket, :edit_error, gettext("Invalid square."))}
    end
  end

  @impl true
  def handle_event(
        "put_piece",
        %{
          "edit" => %{
            "square" => square,
            "color" => color,
            "piece" => piece
          }
        },
        socket
      ) do
    with square when is_integer(square) <-
           Square.from_algebraic(square),
         {:ok, piece} <- parse_piece(color, piece) do
      draft =
        socket.assigns.position
        |> PositionDraft.new()
        |> PositionDraft.put_piece(square, piece)

      edit_position(socket, draft)
    else
      {:error, :invalid_square} ->
        {:noreply, assign(socket, :edit_error, gettext("Invalid square."))}

      {:error, :invalid_piece} ->
        {:noreply, assign(socket, :edit_error, gettext("Invalid piece."))}
    end
  end

  @impl true
  def handle_event(
        "set_side_to_move",
        %{"edit" => %{"side_to_move" => side_to_move}},
        socket
      ) do
    case parse_side_to_move(side_to_move) do
      {:ok, side_to_move} ->
        draft =
          socket.assigns.position
          |> PositionDraft.new()
          |> PositionDraft.set_side_to_move(side_to_move)

        edit_position(socket, draft)

      {:error, :invalid_side_to_move} ->
        {:noreply, assign(socket, :edit_error, gettext("Invalid side to move."))}
    end
  end

  @impl true
  def handle_event(
        "set_castling_right",
        %{
          "edit" => %{
            "right" => right,
            "enabled" => enabled
          }
        },
        socket
      ) do
    with {:ok, right} <- parse_castling_right(right),
         {:ok, enabled} <- parse_boolean(enabled) do
      draft =
        socket.assigns.position
        |> PositionDraft.new()
        |> PositionDraft.set_castling_right(right, enabled)

      edit_position(socket, draft)
    else
      {:error, :invalid_castling_right} ->
        {:noreply, assign(socket, :edit_error, gettext("Invalid castling right."))}

      {:error, :invalid_boolean} ->
        {:noreply, assign(socket, :edit_error, gettext("Invalid castling value."))}
    end
  end

  @impl true
  def handle_event(
        "set_en_passant",
        %{"edit" => %{"en_passant" => en_passant}},
        socket
      ) do
    case parse_en_passant(en_passant) do
      {:ok, en_passant} ->
        draft =
          socket.assigns.position
          |> PositionDraft.new()
          |> PositionDraft.set_en_passant(en_passant)

        edit_position(socket, draft)

      {:error, :invalid_en_passant} ->
        {:noreply,
         assign(
           socket,
           :edit_error,
           gettext("Invalid en passant square.")
         )}
    end
  end

  @impl true
  def handle_event(
        "promote_variation",
        _params,
        socket
      ) do
    case Analyses.promote(
           socket.assigns.selected_analysis_id,
           socket.assigns.current_path
         ) do
      {:ok, analysis, revision, resulting_path} ->
        socket =
          socket
          |> assign(:analysis_revision, revision)
          |> assign_current_occurrence(analysis, resulting_path)

        {:noreply, socket}

      {:error, :node_not_found} ->
        {:noreply, socket}

      {:error, :root} ->
        {:noreply, socket}

      {:error, :analysis_not_found} ->
        {:noreply, socket}

      {:error, :conflict} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "remove_subtree",
        _params,
        socket
      ) do
    case Analyses.remove(
           socket.assigns.selected_analysis_id,
           socket.assigns.current_path
         ) do
      {:ok, analysis, revision, resulting_path} ->
        socket =
          socket
          |> assign(:analysis_revision, revision)
          |> assign_current_occurrence(analysis, resulting_path)

        {:noreply, socket}

      {:error, :node_not_found} ->
        {:noreply, socket}

      {:error, :root} ->
        {:noreply, socket}

      {:error, :analysis_not_found} ->
        {:noreply, socket}

      {:error, :conflict} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "set_comment",
        %{"comment" => %{"text" => comment}},
        socket
      ) do
    case Analyses.set_comment(
           socket.assigns.selected_analysis_id,
           socket.assigns.current_path,
           comment
         ) do
      {:ok, analysis, revision} ->
        socket =
          socket
          |> assign(:analysis_revision, revision)
          |> assign_current_occurrence(
            analysis,
            socket.assigns.current_path
          )

        {:noreply, socket}

      {:error, :node_not_found} ->
        {:noreply, socket}

      {:error, :analysis_not_found} ->
        {:noreply, socket}

      {:error, :conflict} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "navigate_path",
        %{"path" => encoded_path},
        %{assigns: %{analysis: analysis}} = socket
      ) do
    path = parse_path(encoded_path)

    if Analysis.Analysis.node_at(analysis, path) do
      {:noreply, assign_current_occurrence(socket, analysis, path)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "create_analysis",
        %{"analysis" => %{"id" => analysis_id}},
        socket
      ) do
    case Analyses.create(analysis_id) do
      {:ok, _analysis, _revision} ->
        :ok = Rooms.add_analysis(socket.assigns.room_id, analysis_id)

        {:noreply,
         assign(socket,
           create_analysis_error: nil
         )}

      {:error, :already_exists} ->
        {:noreply,
         assign(
           socket,
           :create_analysis_error,
           gettext("Analysis already exists.")
         )}

      {:error, {:position_store, _reason}} ->
        {:noreply,
         assign(
           socket,
           :create_analysis_error,
           gettext("Position storage is temporarily unavailable.")
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <h1>{gettext("Room")} {@room_id}</h1>
      
      <%= if @position_error do %>
        <p id="position-error" role="alert">
          {@position_error}
        </p>
      <% end %>
      
      <form id="create-analysis-form" phx-submit="create_analysis">
        <input
          type="text"
          name="analysis[id]"
          placeholder={gettext("Analysis ID")}
          required
        />
        <button type="submit">
          {gettext("Create analysis")}
        </button>
      </form>
      
      <%= if @create_analysis_error do %>
        <p id="create-analysis-error" role="alert">
          {@create_analysis_error}
        </p>
      <% end %>
      
      <form id="add-analysis-form" phx-submit="add_analysis">
        <input
          type="text"
          name="analysis[id]"
          placeholder={gettext("Analysis ID")}
          required
        />
        <button type="submit">
          {gettext("Add analysis")}
        </button>
      </form>
      
      <%= if @add_analysis_error do %>
        <p role="alert">{@add_analysis_error}</p>
      <% end %>
      
      <%= if @room.analysis_ids == [] do %>
        <p>{gettext("No analyses in this room.")}</p>
      <% else %>
        <ul>
          <li :for={analysis_id <- @room.analysis_ids}>
            <span>{analysis_id}</span>
            <button
              id={"select-analysis-#{analysis_id}"}
              type="button"
              phx-click="select_analysis"
              phx-value-analysis_id={analysis_id}
            >
              {gettext("Select")}
            </button>
            
            <button
              id={"remove-analysis-#{analysis_id}"}
              type="button"
              phx-click="remove_analysis"
              phx-value-analysis_id={analysis_id}
            >
              {gettext("Remove")}
            </button>
          </li>
        </ul>
        
        <%= if @selected_analysis_id do %>
          <section id="selected-analysis">
            <h2>{gettext("Selected analysis")}</h2>
            
            <p id="selected-analysis-id">
              {@selected_analysis_id}
            </p>
            
            <p id="selected-analysis-revision">
              {gettext("Revision")} {@analysis_revision}
            </p>
            
            <p id="current-path">
              {gettext("Path")} {inspect(@current_path)}
            </p>
            
            <MoveTree.move_tree
              analysis={@analysis}
              root_position={@root_position}
              locale={@locale}
            /> <ChessBoard.chess_board position={@position} />
            <PositionEditor.position_editor
              position={@position}
              edit_error={@edit_error}
            />
            <form id="play-move-form" phx-submit="play_move">
              <input
                type="text"
                name="move[from]"
                placeholder={gettext("From")}
                required
              />
              <input
                type="text"
                name="move[to]"
                placeholder={gettext("To")}
                required
              />
              <button type="submit">
                {gettext("Play move")}
              </button>
            </form>
            
            <%= if @move_error do %>
              <p id="move-error" role="alert">{@move_error}</p>
            <% end %>
             <% current_node = Analysis.Analysis.node_at(@analysis, @current_path) %>
            <div id="current-comment">
              <%= if comment = Node.comment(current_node) do %>
                {comment}
              <% else %>
                {gettext("No comment")}
              <% end %>
            </div>
            
            <form id="comment-form" phx-submit="set_comment">
              <textarea name="comment[text]">{Node.comment(current_node)}</textarea>
              <button type="submit">
                {gettext("Save comment")}
              </button>
            </form>
            
            <button
              :if={promotable_path?(@current_path)}
              id="promote-variation"
              type="button"
              phx-click="promote_variation"
            >
              {gettext("Promote variation")}
            </button>
            
            <button
              :if={@current_path != []}
              id="remove-subtree"
              type="button"
              phx-click="remove_subtree"
            >
              {gettext("Remove subtree")}
            </button>
            
            <button
              :if={@current_path != []}
              id="navigate-parent"
              type="button"
              phx-click="navigate_parent"
            >
              {gettext("Parent")}
            </button>
            
            <button
              :for={{child, index} <- Enum.with_index(Node.children(current_node))}
              id={"navigate-child-#{index}"}
              type="button"
              phx-click="navigate_child"
              phx-value-index={index}
            >
              {transition_label(
                @position,
                Node.transition(child),
                @locale
              )}
            </button>
          </section>
        <% end %>
      <% end %>
    </main>
    """
  end

  defp subscribe_to_analysis(socket, analysis_id) do
    if connected?(socket) do
      case socket.assigns.selected_analysis_id do
        nil ->
          :ok

        ^analysis_id ->
          :ok

        previous_analysis_id ->
          :ok = AnalysisEvents.unsubscribe(previous_analysis_id)
      end

      :ok = AnalysisEvents.subscribe(analysis_id)
    end

    :ok
  end

  defp play_move(socket, move) do
    case Analyses.play(
           socket.assigns.selected_analysis_id,
           socket.assigns.current_path,
           move
         ) do
      {:ok, analysis, revision, resulting_path} ->
        socket =
          socket
          |> assign(
            analysis_revision: revision,
            move_error: nil
          )
          |> assign_current_occurrence(analysis, resulting_path)

        {:noreply, socket}

      {:error, :illegal_move} ->
        {:noreply, assign(socket, :move_error, gettext("Illegal move."))}

      {:error, :node_not_found} ->
        {:noreply, assign(socket, :move_error, gettext("Position no longer exists."))}

      {:error, :position_not_found} ->
        {:noreply, assign(socket, :move_error, gettext("Position not found."))}

      {:error, :analysis_not_found} ->
        {:noreply, assign(socket, :move_error, gettext("Analysis not found."))}

      {:error, :conflict} ->
        {:noreply, assign(socket, :move_error, gettext("Analysis changed. Try again."))}

      {:error, {:position_store, _reason}} ->
        {:noreply,
         assign(
           socket,
           :move_error,
           gettext("Position storage is temporarily unavailable.")
         )}
    end
  end

  defp edit_position(socket, draft) do
    case Analyses.edit(
           socket.assigns.selected_analysis_id,
           socket.assigns.current_path,
           draft
         ) do
      {:ok, analysis, revision, resulting_path} ->
        socket =
          socket
          |> assign(
            analysis_revision: revision,
            edit_error: nil
          )
          |> assign_current_occurrence(analysis, resulting_path)

        {:noreply, socket}

      {:error, {:invalid_position, _reasons}} ->
        {:noreply, assign(socket, :edit_error, gettext("Invalid position."))}

      {:error, :node_not_found} ->
        {:noreply, assign(socket, :edit_error, gettext("Position no longer exists."))}

      {:error, :analysis_not_found} ->
        {:noreply, assign(socket, :edit_error, gettext("Analysis not found."))}

      {:error, :conflict} ->
        {:noreply, assign(socket, :edit_error, gettext("Analysis changed. Try again."))}

      {:error, {:position_store, _reason}} ->
        {:noreply,
         assign(
           socket,
           :edit_error,
           gettext("Position storage is temporarily unavailable.")
         )}
    end
  end

  defp assign_current_occurrence(
         socket,
         analysis,
         path
       ) do
    node =
      Analysis.Analysis.node_at(
        analysis,
        path
      )

    position_id =
      Node.position_id(node)

    case PositionStore.get(position_id) do
      {:ok, position} ->
        assign(
          socket,
          analysis: analysis,
          current_path: path,
          position: position,
          position_error: nil
        )

      :not_found ->
        assign(
          socket,
          :position_error,
          gettext("Position not found.")
        )

      {:error, _reason} ->
        assign(
          socket,
          :position_error,
          gettext("Position storage is temporarily unavailable.")
        )
    end
  end

  defp parse_piece(color, piece) do
    case {color, piece} do
      {"white", "king"} -> {:ok, {:white, :king}}
      {"white", "queen"} -> {:ok, {:white, :queen}}
      {"white", "rook"} -> {:ok, {:white, :rook}}
      {"white", "bishop"} -> {:ok, {:white, :bishop}}
      {"white", "knight"} -> {:ok, {:white, :knight}}
      {"white", "pawn"} -> {:ok, {:white, :pawn}}
      {"black", "king"} -> {:ok, {:black, :king}}
      {"black", "queen"} -> {:ok, {:black, :queen}}
      {"black", "rook"} -> {:ok, {:black, :rook}}
      {"black", "bishop"} -> {:ok, {:black, :bishop}}
      {"black", "knight"} -> {:ok, {:black, :knight}}
      {"black", "pawn"} -> {:ok, {:black, :pawn}}
      _ -> {:error, :invalid_piece}
    end
  end

  defp parse_side_to_move("white"), do: {:ok, :white}
  defp parse_side_to_move("black"), do: {:ok, :black}
  defp parse_side_to_move(_side), do: {:error, :invalid_side_to_move}

  defp parse_castling_right("white_kingside"),
    do: {:ok, :white_kingside}

  defp parse_castling_right("white_queenside"),
    do: {:ok, :white_queenside}

  defp parse_castling_right("black_kingside"),
    do: {:ok, :black_kingside}

  defp parse_castling_right("black_queenside"),
    do: {:ok, :black_queenside}

  defp parse_castling_right(_right),
    do: {:error, :invalid_castling_right}

  defp parse_boolean("true"), do: {:ok, true}
  defp parse_boolean("false"), do: {:ok, false}
  defp parse_boolean(_value), do: {:error, :invalid_boolean}

  defp parse_en_passant("none"), do: {:ok, nil}

  defp parse_en_passant(square) do
    case Square.from_algebraic(square) do
      square when is_integer(square) ->
        {:ok, square}

      {:error, :invalid_square} ->
        {:error, :invalid_en_passant}
    end
  end

  defp promotable_path?([]), do: false

  defp promotable_path?(path) do
    List.last(path) > 0
  end

  defp transition_label(position, transition, locale) do
    case ChessNotation.format(position, transition, locale) do
      {:ok, notation} ->
        notation

      :not_applicable ->
        gettext("Edited position")

      {:error, :illegal_move} ->
        gettext("Invalid move")
    end
  end

  defp parse_path(""), do: []

  defp parse_path(path) do
    path
    |> String.split(",")
    |> Enum.map(&String.to_integer/1)
  end

  defp select_analysis(
         socket,
         analysis_id
       ) do
    if analysis_id in socket.assigns.room.analysis_ids do
      case Analyses.get(analysis_id) do
        {:ok, analysis, revision} ->
          root =
            Analysis.Analysis.root(analysis)

          case PositionStore.get(Node.position_id(root)) do
            {:ok, root_position} ->
              subscribe_to_analysis(
                socket,
                analysis_id
              )

              socket
              |> assign(
                selected_analysis_id: analysis_id,
                analysis_revision: revision,
                root_position: root_position,
                position_error: nil
              )
              |> assign_current_occurrence(
                analysis,
                []
              )

            :not_found ->
              assign(
                socket,
                :position_error,
                gettext("Position not found.")
              )

            {:error, _reason} ->
              assign(
                socket,
                :position_error,
                gettext("Position storage is temporarily unavailable.")
              )
          end

        :not_found ->
          socket
      end
    else
      socket
    end
  end
end
