defmodule Web.DisplayNameTest do
  use ExUnit.Case, async: true

  alias Web.DisplayName

  test "generated names use the curated English words and a two-digit number" do
    adjectives = ~w(Brave Calm Clever Daring Elegant Fierce Gentle Happy Jolly Keen
      Kind Lively Mighty Nimble Proud Quick Rustic Serene Swift Valiant Wise)

    animals = ~w(Badger Beaver Bunny Cheetah Cobra Falcon Ferret Fox Gecko Hawk
      Heron Lynx Moose Otter Owl Panda Raven Rhino Skunk Tiger Turtle Wolf Zebra)

    for _ <- 1..100 do
      assert [adjective, animal, number] = String.split(DisplayName.generate(), " ")
      assert adjective in adjectives
      assert animal in animals
      assert number =~ ~r/\A[1-9][0-9]\z/
    end
  end
end
