defmodule Web.ReturnTo do
  @moduledoc """
  Sanitizes browser-supplied post-login and post-logout return paths.

  Only internal room paths are accepted, so a crafted value can never turn a
  login or logout into an open redirect: the worst case is the room page's
  own not-found message. Anything else falls back to `nil`, which callers
  replace with the home path.
  """

  @room_path_regex ~r{\A/rooms/[^/?#]+\z}

  @doc "Returns the path when it is a single-segment room path, otherwise nil."
  @spec sanitize(term()) :: String.t() | nil
  def sanitize(path) when is_binary(path) do
    if byte_size(path) <= 64 and Regex.match?(@room_path_regex, path), do: path
  end

  def sanitize(_), do: nil
end
