defmodule Chess.PositionHash do
  @moduledoc """
  Calculates hashes for chess positions.
  """

  alias Chess.Position
  alias Chess.PositionCodec

  @type t :: <<_::256>>

  @spec hash(Position.t()) :: t()
  def hash(%Position{} = position) do
    position
    |> PositionCodec.encode()
    |> then(&:crypto.hash(:sha256, &1))
  end
end
