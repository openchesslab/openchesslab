defmodule Chess.PositionCanonicalizer do
  alias Chess.Position
  alias Chess.PositionCodec
  alias Chess.PositionTransform

  @spec encode(Position.t()) :: binary()
  def encode(%Position{} = position) do
    normal = PositionCodec.encode(position)
    swapped = position |> PositionTransform.swap_colors() |> PositionCodec.encode()

    min(normal, swapped)
  end
end
