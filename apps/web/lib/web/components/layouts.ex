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
end
