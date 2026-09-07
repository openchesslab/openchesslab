defmodule Chess.PositionHash do
  @moduledoc """
  Calculates hashes for chess positions.
  """

  alias Chess.Position
  alias Chess.PositionCodec

  @algorithm :sha256

  @type t :: <<_::256>>

  @spec hash(Position.t()) :: t()
  def hash(%Position{} = position) do
    position
    |> PositionCodec.encode()
    |> hash()
  end

  @spec hash(binary()) :: t()
  def hash(data) when is_binary(data) do
    :crypto.hash(@algorithm, data)
  end
end
