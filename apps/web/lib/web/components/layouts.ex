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

  @tour_steps [
    {"tour.boardTitle", "tour.boardBody"},
    {"tour.analysesTitle", "tour.analysesBody"},
    {"tour.movesTitle", "tour.movesBody"},
    {"tour.engineTitle", "tour.engineBody"},
    {"tour.importTitle", "tour.importBody"},
    {"tour.searchTitle", "tour.searchBody"},
    {"tour.helpTitle", "tour.helpBody"}
  ]

  def tour_steps_count, do: length(@tour_steps)
  def tour_step(index), do: Enum.at(@tour_steps, max(index - 1, 0), hd(@tour_steps))

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
