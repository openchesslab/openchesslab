defmodule Web.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use Web, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content. The app.html.heex file
  # contains your application menu, sidebar, or similar.
  embed_templates("layouts/*")

  # Each guided-tour step names the `data-tour` anchor it highlights. Steps
  # whose anchor is absent (or zero-sized, e.g. hidden on small screens) fall
  # back to a centered card so the tour never breaks.
  @tour_steps [
    {"board", "tour.boardTitle", "tour.boardBody"},
    {"analyses", "tour.analysesTitle", "tour.analysesBody"},
    {"moves", "tour.movesTitle", "tour.movesBody"},
    {"engine", "tour.engineTitle", "tour.engineBody"},
    {"import", "tour.importTitle", "tour.importBody"},
    {"search", "tour.searchTitle", "tour.searchBody"},
    {"help", "tour.helpTitle", "tour.helpBody"}
  ]

  def tour_steps_count, do: length(@tour_steps)
  def tour_step(index), do: Enum.at(@tour_steps, max(index - 1, 0), hd(@tour_steps))

  # One keyboard-shortcut row: the action on the left, its keys on the right.
  # Keys are <kbd> elements (the semantic element for user input); the key cell
  # never wraps so a combination always stays on one line.
  attr :label, :string, required: true
  slot :inner_block, required: true

  defp shortcut_row(assigns) do
    ~H"""
    <div class="flex justify-between gap-4">
      <dt>{@label}</dt><dd class="m-0 shrink-0 whitespace-nowrap font-mono text-muted">
        {render_slot(@inner_block)}
      </dd>
    </div>
    """
  end

  # The account modal's sync stamp: "2026-10-16 14:05".
  defp format_synced(%NaiveDateTime{} = synced_at),
    do: Calendar.strftime(synced_at, "%Y-%m-%d %H:%M")

  defp format_synced(_), do: ""

  def next_theme("system"), do: "light"
  def next_theme("light"), do: "dark"
  def next_theme("dark"), do: "system"

  def theme_icon("system"), do: "monitor"
  def theme_icon("light"), do: "sun"
  def theme_icon("dark"), do: "moon"

  def theme_cycle_label(theme, locale) do
    Web.I18n.t("theme.cycle", locale, %{
      current: Web.I18n.t("theme." <> theme, locale),
      next: Web.I18n.t("theme." <> next_theme(theme), locale)
    })
  end
end
