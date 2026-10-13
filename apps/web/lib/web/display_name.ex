defmodule Web.DisplayName do
  @moduledoc """
  Server-generated room display names, such as "Brave Otter 42".

  Curated English words avoid accepting profile data or user-entered names.
  These ephemeral labels are not unique identifiers or proof of authentication.
  """

  @adjectives ~w(Brave Calm Clever Daring Elegant Fierce Gentle Happy Jolly Keen
    Kind Lively Mighty Nimble Proud Quick Rustic Serene Swift Valiant Wise)

  @animals ~w(Badger Beaver Bunny Cheetah Cobra Falcon Ferret Fox Gecko Hawk
    Heron Lynx Moose Otter Owl Panda Raven Rhino Skunk Tiger Turtle Wolf Zebra)

  @spec generate() :: String.t()
  def generate do
    "#{Enum.random(@adjectives)} #{Enum.random(@animals)} #{Enum.random(10..99)}"
  end
end
