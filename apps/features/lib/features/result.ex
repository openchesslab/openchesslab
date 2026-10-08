defmodule Features.Result do
  @moduledoc """
  Versioned outcome of feature extraction: the canonical FEN of the
  analysed position and a map of feature id to value.
  """

  @type t :: %__MODULE__{
          version: String.t(),
          fen: String.t(),
          features: %{String.t() => term()}
        }

  defstruct [:version, :fen, :features]

  @doc "Plain map form with string keys throughout, ready for JSON encoding."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = result) do
    %{"version" => result.version, "fen" => result.fen, "features" => result.features}
  end
end
