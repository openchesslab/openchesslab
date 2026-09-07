defmodule Chess.PositionKey do
  @moduledoc """
  Generates keys for chess positions.

  Exact keys represent the complete position identity.

  Equivalent keys represent positions that are considered equivalent
  according to a specified equivalence rule.
  """

  alias Chess.Position
  alias Chess.PositionCodec
  alias Chess.PositionHash
  alias Chess.PositionTransform

  @type equivalence :: :color_swap

  @spec exact(Position.t()) :: binary()
  def exact(%Position{} = position) do
    PositionCodec.encode(position)
  end

  @spec exact_hash(Position.t()) :: PositionHash.t()
  def exact_hash(%Position{} = position) do
    PositionHash.hash(position)
  end

  @spec equivalent(Position.t(), equivalence()) :: binary()
  def equivalent(%Position{} = position, :color_swap) do
    normal = PositionCodec.encode(position)

    swapped =
      position
      |> PositionTransform.swap_colors()
      |> PositionCodec.encode()

    min(normal, swapped)
  end

  @spec equivalent_hash(Position.t(), equivalence()) :: PositionHash.t()
  def equivalent_hash(%Position{} = position, equivalence) do
    position
    |> equivalent(equivalence)
    |> PositionHash.hash()
  end
end
