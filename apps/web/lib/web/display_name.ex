defmodule Web.DisplayName do
  @moduledoc """
  Server-generated display names, such as "Brave Otter 42".

  Curated English words avoid accepting profile data or user-entered names.
  Room labels are ephemeral (`generate/0`) and neither unique identifiers nor
  proof of authentication. `for_user/1` derives a stable label per internal
  user id — the account identity shown in the account menu — and
  `name_color/1` gives each label a deterministic, theme-adaptive badge color.
  """

  @adjectives ~w(Brave Calm Clever Daring Elegant Fierce Gentle Happy Jolly Keen
    Kind Lively Mighty Nimble Proud Quick Rustic Serene Swift Valiant Wise)

  @animals ~w(Badger Beaver Bunny Cheetah Cobra Falcon Ferret Fox Gecko Hawk
    Heron Lynx Moose Otter Owl Panda Raven Rhino Skunk Tiger Turtle Wolf Zebra)

  @spec generate() :: String.t()
  def generate do
    "#{Enum.random(@adjectives)} #{Enum.random(@animals)} #{Enum.random(10..99)}"
  end

  @doc """
  The stable account label for a user: the same user id always derives the
  same name. Deterministic from the internal id — no profile data involved.
  """
  @spec for_user(String.t()) :: String.t()
  def for_user(user_id) when is_binary(user_id) do
    <<a, b, n, _rest::binary>> = :crypto.hash(:sha256, "display-name:" <> user_id)

    "#{Enum.at(@adjectives, rem(a, length(@adjectives)))} #{Enum.at(@animals, rem(b, length(@animals)))} #{rem(n, 90) + 10}"
  end

  @doc "Two-letter uppercase initials for a display name, e.g. \"Wise Otter 42\" → \"WO\"."
  @spec initials(String.t()) :: String.t()
  def initials(name) when is_binary(name) do
    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end

  @doc """
  A deterministic badge color for a display name: a hue from the name's hash
  with fixed saturation/lightness, so white initials contrast in both themes.
  """
  @spec name_color(String.t()) :: String.t()
  def name_color(name) when is_binary(name) do
    <<hue, _rest::binary>> = :crypto.hash(:sha256, "display-color:" <> name)
    "hsl(#{rem(hue * 3, 360)} 55% 45%)"
  end
end
