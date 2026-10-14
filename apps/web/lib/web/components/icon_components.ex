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
          <circle cx="11" cy="11" r="7" /> <path d="m20 20-3.5-3.5" />
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
          <rect x="2" y="3" width="20" height="14" rx="2" /> <path d="M8 21h8M12 17v4" />
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
        <% "star" -> %>
          <path d="M12 17.27 18.18 21l-1.64-7.03L22 9.24l-7.19-.61L12 2 9.19 8.63 2 9.24l5.46 4.73L5.82 21z" />
        <% "person" -> %>
          <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" />
          <circle cx="12" cy="7" r="4" />
        <% "library" -> %>
          <path d="m16 6 4 14" />
          <path d="M12 6v14" />
          <path d="M8 8v12" />
          <path d="M4 4v16" />
        <% "logout" -> %>
          <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" />
          <path d="m16 17 5-5-5-5" />
          <path d="M21 12H9" />
        <% "link" -> %>
          <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71" />
          <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71" />
        <% "last" -> %>
          <path d="M19 5v14M4 6l9 6-9 6z" />
        <% _ -> %>
          <circle cx="12" cy="12" r="1" />
      <% end %>
    </svg>
    """
  end

  # The lichess knight mark, inlined from the lila project
  # (https://github.com/lichess-org/lila), licensed AGPLv3 — compatible with
  # this GPL-3.0-or-later project; see priv/NOTICE.md. currentColor keeps it
  # visible on both themes.
  attr :class, :string, default: "h-4 w-4"

  def lichess_mark(assigns) do
    ~H"""
    <svg
      viewBox="0 0 50 50"
      class={@class}
      aria-hidden="true"
      focusable="false"
      fill="currentColor"
      stroke="currentColor"
      stroke-linejoin="round"
    >
      <path d="M38.956.5c-3.53.418-6.452.902-9.286 2.984C5.534 1.786-.692 18.533.68 29.364 3.493 50.214 31.918 55.785 41.329 41.7c-7.444 7.696-19.276 8.752-28.323 3.084S-.506 27.392 4.683 17.567C9.873 7.742 18.996 4.535 29.03 6.405c2.43-1.418 5.225-3.22 7.655-3.187l-1.694 4.86 12.752 21.37c-.439 5.654-5.459 6.112-5.459 6.112-.574-1.47-1.634-2.942-4.842-6.036-3.207-3.094-17.465-10.177-15.788-16.207-2.001 6.967 10.311 14.152 14.04 17.663 3.73 3.51 5.426 6.04 5.795 6.756 0 0 9.392-2.504 7.838-8.927L37.4 7.171z" />
    </svg>
    """
  end

  # The Google "G" mark, per Google's sign-in button branding guidelines: the
  # standard-color G accompanies a localizable call to action; see
  # priv/NOTICE.md.
  attr :class, :string, default: "h-4 w-4"

  def google_mark(assigns) do
    ~H"""
    <svg viewBox="0 0 48 48" class={@class} aria-hidden="true" focusable="false">
      <path
        fill="#EA4335"
        d="M24 9.5c3.54 0 6.71 1.22 9.19 3.6l6.85-6.85C35.9 1.39 30.44 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"
      />
      <path
        fill="#4285F4"
        d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"
      />
      <path
        fill="#FBBC05"
        d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"
      />
      <path
        fill="#34A853"
        d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"
      />
    </svg>
    """
  end
end
