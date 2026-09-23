defmodule Web.RoomLive do
  use Web, :live_view

  alias Analysis.Game
  alias Analysis.GameEvents
  alias Analysis.Games
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
  def mount(%{"room_id" => room_id}, session, socket) do
    locale = Map.get(session, "locale", "nl")
    Gettext.put_locale(Web.Gettext, locale)

    {:ok, room} = Rooms.start_room(room_id)

    if connected?(socket) do
      :ok = RoomEvents.subscribe(room_id)
    end

    {:ok,
     assign(socket,
       locale: locale,
       room_id: room_id,
       room: room,
       add_game_error: nil,
       move_error: nil,
       edit_error: nil,
       selected_game_id: nil,
       game: nil,
       game_revision: nil,
       current_path: [],
       selected_square: nil,
       root_position: nil,
       position: nil
     )}
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
        {:game_changed, game_id},
        %{assigns: %{selected_game_id: game_id}} = socket
      ) do
    case Games.get(game_id) do
      {:ok, game, revision} ->
        current_path =
          Game.reconcile_path(
            socket.assigns.game,
            game,
            socket.assigns.current_path
          )

        socket =
          socket
          |> assign(:game_revision, revision)
          |> assign_current_occurrence(game, current_path)

        {:noreply, socket}

      :not_found ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "add_game",
        %{"game" => %{"id" => game_id}},
        socket
      ) do
    case Games.get(game_id) do
      {:ok, _game, _revision} ->
        :ok = Rooms.add_game(socket.assigns.room_id, game_id)

        {:noreply, assign(socket, :add_game_error, nil)}

      :not_found ->
        {:noreply, assign(socket, :add_game_error, gettext("Game not found."))}
    end
  end

  @impl true
  def handle_event(
        "remove_game",
        %{"game_id" => game_id},
        socket
      ) do
    :ok = Rooms.remove_game(socket.assigns.room_id, game_id)

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "select_game",
        %{"game_id" => game_id},
        socket
      ) do
    case Games.get(game_id) do
      {:ok, game, revision} ->
        subscribe_to_game(socket, game_id)
        root = Game.root(game)
        {:ok, root_position} = PositionStore.get(Node.position_id(root))

        socket =
          socket
          |> assign(
            selected_game_id: game_id,
            game_revision: revision,
            root_position: root_position
          )
          |> assign_current_occurrence(game, [])

        {:noreply, socket}

      :not_found ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "navigate_child",
        %{"index" => index},
        %{assigns: %{game: game, current_path: path}} = socket
      ) do
    child_index = String.to_integer(index)
    new_path = path ++ [child_index]

    if Game.node_at(game, new_path) do
      {:noreply, assign_current_occurrence(socket, game, new_path)}
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
       socket.assigns.game,
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
        {:noreply, assign(socket, :edit_error, "Invalid en passant square.")}
    end
  end

  @impl true
  def handle_event(
        "promote_variation",
        _params,
        socket
      ) do
    case Games.promote(
           socket.assigns.selected_game_id,
           socket.assigns.current_path
         ) do
      {:ok, game, revision, resulting_path} ->
        socket =
          socket
          |> assign(:game_revision, revision)
          |> assign_current_occurrence(game, resulting_path)

        {:noreply, socket}

      {:error, :node_not_found} ->
        {:noreply, socket}

      {:error, :root} ->
        {:noreply, socket}

      {:error, :game_not_found} ->
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
    case Games.remove(
           socket.assigns.selected_game_id,
           socket.assigns.current_path
         ) do
      {:ok, game, revision, resulting_path} ->
        socket =
          socket
          |> assign(:game_revision, revision)
          |> assign_current_occurrence(game, resulting_path)

        {:noreply, socket}

      {:error, :node_not_found} ->
        {:noreply, socket}

      {:error, :root} ->
        {:noreply, socket}

      {:error, :game_not_found} ->
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
    case Games.set_comment(
           socket.assigns.selected_game_id,
           socket.assigns.current_path,
           comment
         ) do
      {:ok, game, revision} ->
        socket =
          socket
          |> assign(:game_revision, revision)
          |> assign_current_occurrence(
            game,
            socket.assigns.current_path
          )

        {:noreply, socket}

      {:error, :node_not_found} ->
        {:noreply, socket}

      {:error, :game_not_found} ->
        {:noreply, socket}

      {:error, :conflict} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "navigate_path",
        %{"path" => encoded_path},
        %{assigns: %{game: game}} = socket
      ) do
    path = parse_path(encoded_path)

    if Game.node_at(game, path) do
      {:noreply, assign_current_occurrence(socket, game, path)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <h1>Room {@room_id}</h1>

      <form id="add-game-form" phx-submit="add_game">
        <input
          type="text"
          name="game[id]"
          placeholder="Game ID"
          required
        />
        <button type="submit">
          Add game
        </button>
      </form>

      <%= if @add_game_error do %>
        <p role="alert">{@add_game_error}</p>
      <% end %>

      <%= if @room.game_ids == [] do %>
        <p>No games in this room.</p>
      <% else %>
        <ul>
          <li :for={game_id <- @room.game_ids}>
            <span>{game_id}</span>

            <button
              id={"select-game-#{game_id}"}
              type="button"
              phx-click="select_game"
              phx-value-game_id={game_id}
            >
              Select
            </button>

            <button
              id={"remove-game-#{game_id}"}
              type="button"
              phx-click="remove_game"
              phx-value-game_id={game_id}
            >
              Remove
            </button>
          </li>
        </ul>

        <%= if @selected_game_id do %>
          <section id="selected-game">
            <h2>{gettext("Selected game")}</h2>

            <p id="selected-game-id">
              {@selected_game_id}
            </p>

            <p id="selected-game-revision">
              Revision {@game_revision}
            </p>

            <p id="current-path">
              Path {inspect(@current_path)}
            </p>

            <MoveTree.move_tree
              game={@game}
              root_position={@root_position}
              locale={@locale}
            />

            <ChessBoard.chess_board position={@position} />

            <PositionEditor.position_editor
              position={@position}
              edit_error={@edit_error}
            />

            <form id="play-move-form" phx-submit="play_move">
              <input
                type="text"
                name="move[from]"
                placeholder="From"
                required
              />

              <input
                type="text"
                name="move[to]"
                placeholder="To"
                required
              />

              <button type="submit">
                Play move
              </button>
            </form>

            <%= if @move_error do %>
              <p id="move-error" role="alert">{@move_error}</p>
            <% end %>

            <% current_node = Game.node_at(@game, @current_path) %>

            <div id="current-comment">
              <%= if comment = Node.comment(current_node) do %>
                {comment}
              <% else %>
                No comment
              <% end %>
            </div>

            <form id="comment-form" phx-submit="set_comment">
              <textarea name="comment[text]">{Node.comment(current_node)}</textarea>

              <button type="submit">
                Save comment
              </button>
            </form>

            <button
              :if={promotable_path?(@current_path)}
              id="promote-variation"
              type="button"
              phx-click="promote_variation"
            >
              Promote variation
            </button>

            <button
              :if={@current_path != []}
              id="remove-subtree"
              type="button"
              phx-click="remove_subtree"
            >
              Remove subtree
            </button>

            <button
              :if={@current_path != []}
              id="navigate-parent"
              type="button"
              phx-click="navigate_parent"
            >
              Parent
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

  defp subscribe_to_game(socket, game_id) do
    if connected?(socket) do
      case socket.assigns.selected_game_id do
        nil ->
          :ok

        ^game_id ->
          :ok

        previous_game_id ->
          :ok = GameEvents.unsubscribe(previous_game_id)
      end

      :ok = GameEvents.subscribe(game_id)
    end

    :ok
  end

  defp play_move(socket, move) do
    case Games.play(
           socket.assigns.selected_game_id,
           socket.assigns.current_path,
           move
         ) do
      {:ok, game, revision, resulting_path} ->
        socket =
          socket
          |> assign(
            game_revision: revision,
            move_error: nil
          )
          |> assign_current_occurrence(game, resulting_path)

        {:noreply, socket}

      {:error, :illegal_move} ->
        {:noreply, assign(socket, :move_error, gettext("Illegal move."))}

      {:error, :node_not_found} ->
        {:noreply, assign(socket, :move_error, gettext("Position no longer exists."))}

      {:error, :position_not_found} ->
        {:noreply, assign(socket, :move_error, gettext("Position not found."))}

      {:error, :game_not_found} ->
        {:noreply, assign(socket, :move_error, gettext("Game not found."))}

      {:error, :conflict} ->
        {:noreply, assign(socket, :move_error, gettext("Game changed. Try again."))}
    end
  end

  defp edit_position(socket, draft) do
    case Games.edit(
           socket.assigns.selected_game_id,
           socket.assigns.current_path,
           draft
         ) do
      {:ok, game, revision, resulting_path} ->
        socket =
          socket
          |> assign(
            game_revision: revision,
            edit_error: nil
          )
          |> assign_current_occurrence(game, resulting_path)

        {:noreply, socket}

      {:error, {:invalid_position, _reasons}} ->
        {:noreply, assign(socket, :edit_error, gettext("Invalid position."))}

      {:error, :node_not_found} ->
        {:noreply, assign(socket, :edit_error, gettext("Position no longer exists."))}

      {:error, :game_not_found} ->
        {:noreply, assign(socket, :edit_error, gettext("Game not found."))}

      {:error, :conflict} ->
        {:noreply, assign(socket, :edit_error, gettext("Game changed. Try again."))}
    end
  end

  defp assign_current_occurrence(socket, game, path) do
    node = Game.node_at(game, path)
    position_id = Node.position_id(node)

    {:ok, position} = PositionStore.get(position_id)

    assign(socket,
      game: game,
      current_path: path,
      position: position
    )
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
end
