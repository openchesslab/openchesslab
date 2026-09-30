defmodule Web.ChessComponents do
  use Web, :html

  alias Chess.Position
  alias Chess.Square

  attr :position, :any, required: true
  attr :locale, :string, default: "en"
  attr :orientation, :string, default: "white"
  attr :board_id, :string, default: "chess-board"
  attr :center, :boolean, default: true
  attr :selected_square, :integer, default: nil
  attr :cursor_square, :integer, default: nil
  attr :legal_targets, :list, default: []
  attr :shapes, :list, default: []
  attr :annotation_color, :string, default: "blue"
  attr :piece_set, :string, default: "merida"
  attr :check_squares, :list, default: []
  attr :last_from, :integer, default: nil
  attr :last_to, :integer, default: nil
  attr :layers, :map, default: %{}
  attr :insights, :map, default: %{}

  def chess_board(assigns) do
    squares =
      for rank <- ranks(assigns.orientation), file <- files(assigns.orientation) do
        square = rank * 8 + file
        {rank, file, square, Position.piece_at(assigns.position, square)}
      end

    assigns =
      assigns
      |> assign(:squares, squares)
      |> assign(:highlight_sides, highlight_sides(assigns.shapes))
      |> assign(:cursor_square, assigns.cursor_square || cursor_for(assigns.position) || 0)

    ~H"""
    <div
      id={@board_id}
      data-board
      data-orientation={@orientation}
      data-annotation-color={@annotation_color}
      data-piece-set={@piece_set}
      role="group"
      aria-label={Web.I18n.t("room.boardHeading")}
      class={[
        "relative min-w-0 w-[min(100%,calc(100dvh-14rem))] max-w-[42rem] select-none touch-none max-[860px]:w-full",
        @center && "mx-auto"
      ]}
      phx-hook="Board"
    >
      <div
        data-board-grid
        class="relative grid aspect-square grid-cols-8 grid-rows-8 overflow-hidden border border-border-strong"
      >
        <%= for {rank, file, square, piece} <- @squares do %>
          <% algebraic = Square.to_algebraic(square) %> <% selected = square == @selected_square %> <% target =
            square in @legal_targets %> <% checked = square in @check_squares %> <% last_move =
            square == @last_from or square == @last_to %> <% {visual_file, visual_rank} =
            visual_coords(square, @orientation) %> <% open_file =
            @layers[:files] && @insights && @insights[:open_files] &&
              file_atom(file) in @insights.open_files %> <% white_attack =
            @layers[:attacks] && @insights && @insights[:attacked_squares] &&
              square in @insights.attacked_squares.white %> <% black_attack =
            @layers[:attacks] && @insights && @insights[:attacked_squares] &&
              square in @insights.attacked_squares.black %> <% white_king_zone =
            @layers[:king_zone] && @insights && @insights[:king_zone] &&
              square in @insights.king_zone.white.squares %> <% black_king_zone =
            @layers[:king_zone] && @insights && @insights[:king_zone] &&
              square in @insights.king_zone.black.squares %> <% white_outpost =
            @layers[:outposts] && @insights && @insights[:outposts] &&
              square in @insights.outposts.white %> <% black_outpost =
            @layers[:outposts] && @insights && @insights[:outposts] &&
              square in @insights.outposts.black %>
          <button
            id={"#{@board_id}-square-#{algebraic}"}
            type="button"
            data-square={square}
            data-piece={if(is_nil(piece), do: nil, else: "true")}
            data-algebraic={algebraic}
            aria-label={square_label(square, piece, @locale)}
            aria-pressed={selected}
            tabindex={if square == @cursor_square or selected, do: 0, else: -1}
            phx-click="board-square"
            phx-value-square={square}
            class={[
              "group relative grid min-h-0 min-w-0 place-items-center border-0 p-0",
              "data-[arrow-start]:shadow-[inset_0_0_0_3px_var(--warning)]",
              light_square?(square) && not last_move && "bg-board-light",
              not light_square?(square) && not last_move && "bg-board-dark",
              last_move && light_square?(square) && "bg-board-move-from",
              last_move && not light_square?(square) && "bg-board-move-to",
              selected && "before:absolute before:inset-0 before:bg-cyan-400/45 before:content-['']",
              checked && "before:absolute before:inset-0 before:bg-red-500/55 before:content-['']",
              target && piece && "ring-4 ring-inset ring-black/30"
            ]}
          >
            <span
              :if={open_file}
              class="pointer-events-none absolute inset-x-[18%] top-0 z-[2] h-full border-x-[3px] border-cyan-700/90 bg-cyan-400/25"
              aria-hidden="true"
            ></span>
            <span
              :if={white_attack}
              class="pointer-events-none absolute inset-0 z-[2] bg-blue-500/20"
              aria-hidden="true"
            ></span>
            <span
              :if={black_attack}
              class="pointer-events-none absolute inset-0 z-[2] bg-red-500/20"
              aria-hidden="true"
            ></span>
            <span
              :if={white_king_zone}
              class="pointer-events-none absolute inset-0 z-[2] ring-2 ring-inset ring-blue-400/70"
              aria-hidden="true"
            ></span>
            <span
              :if={black_king_zone}
              class="pointer-events-none absolute inset-0 z-[2] ring-2 ring-inset ring-red-400/70"
              aria-hidden="true"
            ></span>
            <span
              :if={white_outpost || black_outpost}
              class="pointer-events-none absolute inset-1 z-[2] rounded-full border-2 border-purple-700/70"
              aria-hidden="true"
            ></span>
            <span
              :if={target && is_nil(piece)}
              class="absolute z-10 h-[22%] w-[22%] rounded-full bg-[var(--board-legal)]"
              aria-hidden="true"
            ></span>
            <span
              :if={piece}
              data-piece
              aria-hidden="true"
              class="z-10 block h-[88%] w-[88%] select-none group-data-[drag-source]:invisible"
            ><.piece_icon kind={elem(piece, 1)} color={elem(piece, 0)} piece_set={@piece_set} /></span>
            <span
              :if={(@orientation == "white" and rank == 0) or (@orientation == "black" and rank == 7)}
              aria-hidden="true"
              class={[
                "absolute bottom-0.5 right-1 z-20 text-[.58rem] font-bold leading-none opacity-80",
                light_square?(square) && "text-board-dark",
                not light_square?(square) && "text-board-light"
              ]}
            >{file_label(visual_file, @orientation)}</span>
            <span
              :if={(@orientation == "white" and file == 0) or (@orientation == "black" and file == 7)}
              aria-hidden="true"
              class={[
                "absolute left-1 top-0.5 z-20 text-[.58rem] font-bold leading-none opacity-80",
                light_square?(square) && "text-board-dark",
                not light_square?(square) && "text-board-light"
              ]}
            >{coordinate_rank(visual_rank, @orientation)}</span>
          </button>
        <% end %>
        
        <%= for shape <- @shapes do %>
          <%= if shape.type == :arrow do %>
            <% {x1, y1} = square_center(shape.from, @orientation) %> <% {x2, y2} =
              square_center(shape.to, @orientation) %>
            <svg
              data-shape-key={"arrow-#{shape.from}-#{shape.to}-#{shape.color}"}
              class="pointer-events-none absolute inset-0 z-20 h-full w-full"
              viewBox="0 0 800 800"
              aria-hidden="true"
            >
              <line
                x1={x1}
                y1={y1}
                x2={x2}
                y2={y2}
                stroke={shape_color(shape.color)}
                stroke-width="10"
                stroke-linecap="round"
                opacity=".88"
              />
              <polygon
                points={arrow_head_points(x1, y1, x2, y2)}
                fill={shape_color(shape.color)}
                opacity=".88"
              />
            </svg>
          <% else %>
            <% {visual_file, visual_rank} = visual_coords(shape.square, @orientation) %>
            <div
              data-shape-key={"square-#{shape.square}-#{shape.color}"}
              data-highlight-square={shape.square}
              aria-hidden="true"
              class="pointer-events-none absolute z-10"
              style={[
                "left:#{visual_file * 12.5}%;top:#{visual_rank * 12.5}%;width:12.5%;height:12.5%;",
                highlight_style(
                  Map.get(@highlight_sides, {shape.square, shape.color}, []),
                  shape.color,
                  @orientation
                )
              ]}
            >
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  defp ranks("black"), do: Enum.to_list(0..7)
  defp ranks(_orientation), do: Enum.to_list(7..0//-1)
  defp files("black"), do: Enum.to_list(7..0//-1)
  defp files(_orientation), do: Enum.to_list(0..7)

  defp light_square?(square), do: rem(rem(square, 8) + div(square, 8), 2) == 1

  defp visual_coords(square, "black"), do: {7 - rem(square, 8), div(square, 8)}
  defp visual_coords(square, _orientation), do: {rem(square, 8), 7 - div(square, 8)}

  defp square_center(square, orientation) do
    {file, rank} = visual_coords(square, orientation)
    {file * 100 + 50, rank * 100 + 50}
  end

  defp arrow_head_points(x1, y1, x2, y2) do
    angle = :math.atan2(y2 - y1, x2 - x1)
    base_x = x2 - :math.cos(angle) * 30
    base_y = y2 - :math.sin(angle) * 30
    left_x = base_x + :math.sin(angle) * 17
    left_y = base_y - :math.cos(angle) * 17
    right_x = base_x - :math.sin(angle) * 17
    right_y = base_y + :math.cos(angle) * 17

    [{x2, y2}, {left_x, left_y}, {right_x, right_y}]
    |> Enum.map_join(" ", fn {x, y} -> "#{Float.round(x * 1.0, 1)},#{Float.round(y * 1.0, 1)}" end)
  end

  defp file_label(file, "black"), do: <<?h - file>>
  defp file_label(file, _orientation), do: <<?a + file>>
  defp file_atom(file), do: Enum.at([:a, :b, :c, :d, :e, :f, :g, :h], file)
  defp coordinate_rank(rank, "black"), do: rank + 1
  defp coordinate_rank(rank, _orientation), do: 8 - rank

  defp cursor_for(position) do
    position
    |> Position.pieces()
    |> Enum.find_value(fn
      {square, {side, _kind}} when side == position.side_to_move -> square
      _ -> nil
    end)
  end

  defp square_label(square, nil, locale) do
    Web.I18n.t("room.squareEmpty", locale) <> " " <> Square.to_algebraic(square)
  end

  defp square_label(square, {color, kind}, locale) do
    Web.I18n.t("room.squareOccupied", locale, %{piece: piece_name(kind, color, locale)}) <>
      " " <> Square.to_algebraic(square)
  end

  defp piece_name(kind, color, "nl") do
    color_name = if color == :white, do: "wit", else: "zwart"

    names = %{
      pawn: "pion",
      knight: "paard",
      bishop: "loper",
      rook: "toren",
      queen: "dame",
      king: "koning"
    }

    color_name <> " " <> Map.fetch!(names, kind)
  end

  defp piece_name(kind, color, _locale) do
    color_name = if color == :white, do: "white", else: "black"

    names = %{
      pawn: "pawn",
      knight: "knight",
      bishop: "bishop",
      rook: "rook",
      queen: "queen",
      king: "king"
    }

    color_name <> " " <> Map.fetch!(names, kind)
  end

  attr :kind, :any, required: true
  attr :color, :any, required: true
  attr :piece_set, :string, default: "merida"
  attr :class, :string, default: ""

  def piece_icon(assigns) do
    set = if assigns.piece_set in ["merida", "cburnett"], do: assigns.piece_set, else: "merida"
    src = "/images/pieces/#{set}/#{assigns.color}_#{assigns.kind}.svg"
    assigns = assign(assigns, :src, src)

    ~H"""
    <img
      src={@src}
      alt=""
      aria-hidden="true"
      draggable="false"
      class={["pointer-events-none h-full w-full object-contain", @class]}
    />
    """
  end

  @highlight_sides [:top, :right, :bottom, :left]

  @doc """
  Computes which sides of each square annotation are on the boundary of its
  colour's region. Adjacent squares of the same colour drop their shared side,
  so a group of highlights reads as one outline instead of a stack of boxes.
  """
  def highlight_sides(shapes) do
    squares =
      for %{type: :square, square: square, color: color} <- shapes, do: {square, color}

    highlighted = MapSet.new(squares)

    Map.new(squares, fn {square, color} ->
      sides =
        Enum.filter(@highlight_sides, fn side ->
          not same_color_neighbor?(highlighted, square, side, color)
        end)

      {{square, color}, sides}
    end)
  end

  defp same_color_neighbor?(highlighted, square, side, color) do
    case side do
      :top -> square + 8 <= 63 and MapSet.member?(highlighted, {square + 8, color})
      :right -> rem(square, 8) < 7 and MapSet.member?(highlighted, {square + 1, color})
      :bottom -> square - 8 >= 0 and MapSet.member?(highlighted, {square - 8, color})
      :left -> rem(square, 8) > 0 and MapSet.member?(highlighted, {square - 1, color})
    end
  end

  defp highlight_style(sides, color, orientation) do
    paint = shape_color(color)

    orientation
    |> visual_sides(sides)
    |> Enum.map_join(fn side -> "border-#{side}:5px solid #{paint};" end)
  end

  defp visual_sides("white", sides), do: sides

  defp visual_sides("black", sides) do
    Enum.map(sides, fn
      :top -> :bottom
      :bottom -> :top
      :left -> :right
      :right -> :left
    end)
  end

  defp shape_color("yellow"), do: "#f2c200"
  defp shape_color("red"), do: "#d6453d"
  defp shape_color("orange"), do: "#e08a1e"
  defp shape_color("purple"), do: "#8b5cf6"
  defp shape_color(_color), do: "#3b6fe0"
end
