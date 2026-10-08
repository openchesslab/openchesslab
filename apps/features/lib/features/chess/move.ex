defmodule Features.Chess.Move do
  @moduledoc """
  A single move: from-square to to-square with an optional promotion piece.
  Castling and en passant are derived from board context.
  """

  defstruct [:from, :to, :promotion]

  @type promotion :: nil | :queens | :rooks | :bishops | :knights

  @type t :: %__MODULE__{
          from: 0..63,
          to: 0..63,
          promotion: promotion()
        }

  @spec new(0..63, 0..63, promotion()) :: t
  def new(from, to, promotion \\ nil) do
    %__MODULE__{from: from, to: to, promotion: promotion}
  end

  @doc ~s(UCI notation, e.g. `"e2e4"` or `"e7e8q"`.)
  @spec to_uci(t) :: String.t()
  def to_uci(%__MODULE__{from: from, to: to, promotion: promotion}) do
    base = Features.Chess.Square.to_string(from) <> Features.Chess.Square.to_string(to)

    case promotion do
      nil -> base
      type -> base <> Map.fetch!(%{queens: "q", rooks: "r", bishops: "b", knights: "n"}, type)
    end
  end
end
