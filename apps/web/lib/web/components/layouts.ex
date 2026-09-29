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

  def theme_button(current, target) do
    base =
      "inline-flex min-h-8 min-w-8 items-center justify-center rounded-md border border-border bg-transparent px-1 py-1 text-foreground hover:bg-panel-hover"

    if current == target do
      base <> " border-accent-strong bg-panel-hover"
    else
      base
    end
  end
end
