defmodule Chess.PositionCanonicalizerTest do
  use ExUnit.Case

  alias Chess.Position
  alias Chess.PositionCanonicalizer
  alias Chess.PositionTransform

  test "same position has same canonical encoding" do
    position = Position.starting_position()

    assert PositionCanonicalizer.encode(position) ==
             PositionCanonicalizer.encode(position)
  end

  test "color-swapped positions have the same canonical encoding" do
    position = Position.starting_position()
    swapped = PositionTransform.swap_colors(position)

    assert PositionCanonicalizer.encode(position) ==
             PositionCanonicalizer.encode(swapped)
  end

  test "canonical encoding is one of the two possible encodings" do
    position = Position.starting_position()

    normal = Chess.PositionCodec.encode(position)

    swapped =
      position
      |> PositionTransform.swap_colors()
      |> Chess.PositionCodec.encode()

    canonical = PositionCanonicalizer.encode(position)

    assert canonical == min(normal, swapped)
  end
end
