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

  test "user labels are stable per user id and use the curated words" do
    id_a = Ecto.UUID.generate()
    id_b = Ecto.UUID.generate()

    assert DisplayName.for_user(id_a) == DisplayName.for_user(id_a)

    assert [adjective, animal, number] = String.split(DisplayName.for_user(id_a), " ")
    assert adjective == String.capitalize(String.downcase(adjective))
    assert number =~ ~r/\A[1-9][0-9]\z/
    # Almost always different users get different labels.
    refute DisplayName.for_user(id_a) == DisplayName.for_user(id_b)
  end

  test "initials and badge colors are deterministic per name" do
    assert DisplayName.initials("Wise Otter 42") == "WO"
    assert DisplayName.initials("Happy Panda 10") == "HP"

    color = DisplayName.name_color("Wise Otter 42")
    assert color == DisplayName.name_color("Wise Otter 42")
    assert color =~ ~r/\Ahsl\(\d{1,3} 55% 45%\)\z/
  end
end
