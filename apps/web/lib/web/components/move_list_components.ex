defmodule Web.MoveListComponents do
  @moduledoc "Accessible paired mainline and nested variation rows for analysis move trees."

  use Phoenix.Component

  import Web.IconComponents, only: [icon: 1]

  attr :rows, :list, required: true
  attr :entries, :list, required: true
  attr :current_path, :list, required: true
  attr :focus_path, :list, required: true
  attr :locale, :string, required: true
  attr :empty_message, :string, required: true
  attr :help_text, :string, required: true

  def move_list(assigns) do
    ~H"""
    <section aria-label={Web.I18n.t("room.movesTab", @locale)}>
      <div
        id="move-list"
        class="max-h-[38vh] min-h-[14rem] space-y-1 overflow-y-auto px-2 py-2 min-[861px]:min-h-[38vh]"
        role="listbox"
        aria-label={Web.I18n.t("room.movesTab", @locale)}
        tabindex={if @entries == [], do: 0, else: -1}
        phx-hook="MoveList"
      >
        <p :if={@rows == []} class="m-1 text-sm text-muted">{@empty_message}</p>

        <%= for row <- @rows do %>
          <%= if row.type == :mainline do %>
            <div
              class="flex flex-wrap items-baseline gap-x-1 gap-y-0.5"
              data-move-row="mainline"
            >
              <%= for move <- row.moves do %>
                <.move_button
                  entry={move.entry}
                  current_path={@current_path}
                  focus_path={@focus_path}
                  locale={@locale}
                  line="main"
                  show_number={move.show_number}
                />
                <div
                  :if={move.entry.comment}
                  class="basis-full border-l-2 border-border-strong pl-2 text-xs italic text-muted"
                >
                  {move.entry.comment}
                </div>
              <% end %>
            </div>
          <% else %>
            <.variation_line
              root={row.root}
              depth={0}
              current_path={@current_path}
              focus_path={@focus_path}
              locale={@locale}
            />
          <% end %>
        <% end %>
      </div>

      <p class="mb-0 mt-2 text-[.68rem] text-faint">{@help_text}</p>
    </section>
    """
  end

  defp variation_line(assigns) do
    assigns = assign(assigns, :items, variation_items(assigns.root))

    ~H"""
    <div
      class={[
        "flex flex-wrap items-baseline gap-x-1 gap-y-0.5 border-l-2 pl-2",
        @depth == 0 && "border-border-strong",
        @depth > 0 && "ml-1.5 basis-full border-border"
      ]}
      data-move-row="variation"
      data-variation-depth={@depth}
    >
      <%= for item <- @items do %>
        <.move_button
          entry={item.entry}
          current_path={@current_path}
          focus_path={@focus_path}
          locale={@locale}
          line="variation"
          show_number={item.show_number}
        />
        <span :if={item.entry.comment} class="text-xs italic text-muted">
          {item.entry.comment}
        </span>

        <.variation_line
          :for={nested <- item.variations}
          root={nested}
          depth={@depth + 1}
          current_path={@current_path}
          focus_path={@focus_path}
          locale={@locale}
        />
      <% end %>
    </div>
    """
  end

  defp move_button(assigns) do
    assigns =
      assigns
      |> assign(:selected, assigns.entry.path == assigns.current_path)
      |> assign(
        :tabstop,
        move_tabstop?(assigns.entry.path, assigns.current_path, assigns.focus_path)
      )

    ~H"""
    <button
      type="button"
      role="option"
      aria-selected={if @selected, do: "true", else: "false"}
      aria-current={if @selected, do: "location", else: nil}
      data-move-path={Enum.join(@entry.path, ",")}
      tabindex={if @tabstop, do: 0, else: -1}
      class={[
        "rounded-control px-1.5 py-0.5 font-mono transition-colors focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-focus",
        @line == "main" && "text-sm font-semibold text-foreground hover:bg-panel-hover",
        @line == "variation" &&
          "text-xs font-normal text-muted hover:bg-panel-hover hover:text-foreground",
        @selected && "bg-highlight/15 text-highlight ring-1 ring-highlight/50 hover:bg-highlight/25"
      ]}
      phx-click="select-path"
      phx-value-path={Enum.join(@entry.path, ",")}
    >
      <%= if @entry.edit? do %>
        <em class="inline-flex items-center gap-1 text-muted not-italic">
          <.icon name="edit" class="h-3 w-3" /> {@entry.label}
        </em>
      <% else %>
        <span :if={@show_number} class="mr-1 text-faint">{@entry.prefix}</span>
        <span>{@entry.label}</span>
        <span :if={@entry.nags != []} class="ml-0.5 font-bold text-warning">
          {nag_glyphs(@entry.nags)}
        </span>
      <% end %>
    </button>
    """
  end

  defp variation_items(root), do: variation_items(root, true)

  defp variation_items(entry, interrupted) do
    children = entry.children
    nested_variations = Enum.drop(children, 1)

    item = %{
      entry: Map.delete(entry, :children),
      show_number: entry.side == :white or interrupted,
      variations: nested_variations
    }

    case children do
      [mainline_child | _] ->
        [item | variation_items(mainline_child, nested_variations != [] or entry.edit?)]

      [] ->
        [item]
    end
  end

  defp move_tabstop?(path, current_path, focus_path) do
    active_path = if focus_path == [], do: current_path, else: focus_path
    path == active_path or (active_path == [] and path == [0])
  end

  defp nag_glyphs(nags), do: Enum.map_join(nags || [], &nag_glyph/1)
  defp nag_glyph(1), do: "!"
  defp nag_glyph(2), do: "?"
  defp nag_glyph(3), do: "‼"
  defp nag_glyph(4), do: "⁇"
  defp nag_glyph(5), do: "⁉"
  defp nag_glyph(6), do: "⁈"
  defp nag_glyph(_nag), do: ""
end
