defmodule Features.Catalogue do
  @moduledoc """
  Registry of all features derived from `docs/POSITION_FEATURES.md`.

  Each section of the spec has its own module returning a list of
  `Features.Feature` structs. Every spec bullet must be claimed by at
  least one feature; `test/features/catalogue_coverage_test.exs` enforces
  this in both directions.
  """

  alias Features.Catalogue.{
    Attacks,
    Center,
    Evaluation,
    Goals,
    Initiative,
    King,
    Lines,
    Material,
    Mobility,
    Motifs,
    Pawns,
    Placement,
    Position,
    Quality,
    Similarity,
    Space,
    Squares,
    State,
    Tactics,
    Tension,
    Threats
  }

  alias Features.Feature

  @pkey {__MODULE__, :features}

  @sections [
    State,
    Material,
    Pawns,
    Placement,
    Mobility,
    Center,
    Space,
    Squares,
    Lines,
    Attacks,
    King,
    Tactics,
    Threats,
    Motifs,
    Goals,
    Tension,
    Quality,
    Initiative,
    Position,
    Evaluation,
    Similarity
  ]

  @doc "All features, in section order."
  @spec all() :: [Feature.t()]
  def all do
    case :persistent_term.get(@pkey, nil) do
      nil ->
        features = Enum.flat_map(@sections, & &1.features())
        :persistent_term.put(@pkey, features)
        features

      features ->
        features
    end
  end

  @doc "All features of one spec section."
  @spec by_section(pos_integer()) :: [Feature.t()]
  def by_section(section) do
    Enum.filter(all(), &(&1.section == section))
  end

  @doc "Look up a feature by id. Raises when unknown."
  @spec fetch!(String.t()) :: Feature.t()
  def fetch!(id) do
    case Enum.find(all(), &(&1.id == id)) do
      nil -> raise ArgumentError, "unknown feature id: #{inspect(id)}"
      feature -> feature
    end
  end
end
