defmodule Web.IconComponents do
  @moduledoc "Small inline SVG icons shared by the LiveView templates."

  use Phoenix.Component

  attr :name, :string, required: true
  attr :class, :string, default: "h-4 w-4"
  attr :up, :boolean, default: false

  def icon(assigns) do
    ~H"""
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.8"
      stroke-linecap="round"
      stroke-linejoin="round"
      class={@class}
      aria-hidden="true"
      focusable="false"
    >
      <%= case @name do %>
        <% "settings" -> %>
          <circle cx="12" cy="12" r="3" />
          <path d="M19.4 15a1.7 1.7 0 0 0 .34 1.87l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.7 1.7 0 0 0-1.87-.34 1.7 1.7 0 0 0-1 1.55V21a2 2 0 1 1-4 0v-.09a1.7 1.7 0 0 0-1.11-1.55 1.7 1.7 0 0 0-1.87.34l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.7 1.7 0 0 0 .34-1.87 1.7 1.7 0 0 0-1.55-1H3a2 2 0 1 1 0-4h.09a1.7 1.7 0 0 0 1.55-1.11 1.7 1.7 0 0 0-.34-1.87l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.7 1.7 0 0 0 1.87.34H9a1.7 1.7 0 0 0 1-1.55V3a2 2 0 1 1 4 0v.09a1.7 1.7 0 0 0 1 1.55 1.7 1.7 0 0 0 1.87-.34l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.7 1.7 0 0 0-.34 1.87V9a1.7 1.7 0 0 0 1.55 1H21a2 2 0 1 1 0 4h-.09a1.7 1.7 0 0 0-1.51 1z" />
        <% "sliders" -> %>
          <path d="M4 21v-7M4 10V3M12 21v-9M12 8V3M20 21v-5M20 12V3M1 14h6M9 8h6M17 16h6" />
        <% "search" -> %>
          <circle cx="11" cy="11" r="7" />
          <path d="m20 20-3.5-3.5" />
        <% "import" -> %>
          <path d="M12 3v12M7 10l5 5 5-5M4 21h16" />
        <% "add" -> %>
          <path d="M12 5v14M5 12h14" />
        <% "copy" -> %>
          <rect x="9" y="9" width="12" height="12" rx="2" />
          <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
        <% "chevron" -> %>
          <path d={if @up, do: "m6 15 6-6 6 6", else: "m6 9 6 6 6-6"} />
        <% "monitor" -> %>
          <rect x="2" y="3" width="20" height="14" rx="2" />
          <path d="M8 21h8M12 17v4" />
        <% "sun" -> %>
          <circle cx="12" cy="12" r="4" />
          <path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M6.34 17.66l-1.41 1.41M19.07 4.93l-1.41 1.41" />
        <% "moon" -> %>
          <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z" />
        <% "tour" -> %>
          <path d="M12 3v18M12 6h6l2 2-2 2h-6M12 14H6l-2 2 2 2h6" />
        <% "close" -> %>
          <path d="M18 6 6 18M6 6l12 12" />
        <% "question" -> %>
          <circle cx="12" cy="12" r="9" />
          <path d="M9.6 9a2.5 2.5 0 1 1 4.5 1.5c-.9 1-2.1 1.2-2.1 3M12 17.5h.01" />
        <% "message" -> %>
          <path d="M21 11.5a8.5 8.5 0 0 1-8.5 8.5 9 9 0 0 1-4-.9L3 21l1.9-5.5a9 9 0 0 1-.9-4A8.5 8.5 0 0 1 12.5 3h.5a8.5 8.5 0 0 1 8 8z" />
          <path d="M8 12h.01M12 12h.01M16 12h.01" />
        <% "flip" -> %>
          <path d="M12 3v18M7 8l5-5 5 5M7 16l5 5 5-5" />
        <% "edit" -> %>
          <path d="m15 5 4 4M4 20l4.5-1L19 8.5a2.12 2.12 0 0 0-3-3L5.5 16 4 20z" />
        <% "eraser" -> %>
          <path d="m7 21-4-4a2 2 0 0 1 0-2.8l8.8-8.8a2 2 0 0 1 2.8 0l6 6a2 2 0 0 1 0 2.8L14 21H7z" />
          <path d="m9 9 8 8M14 21h7" />
        <% "first" -> %>
          <path d="M5 5v14M20 6l-9 6 9 6z" />
        <% "previous" -> %>
          <path d="m15 5-8 7 8 7z" />
        <% "next" -> %>
          <path d="m9 5 8 7-8 7z" />
        <% "last" -> %>
          <path d="M19 5v14M4 6l9 6-9 6z" />
        <% _ -> %>
          <circle cx="12" cy="12" r="1" />
      <% end %>
    </svg>
    """
  end
end
