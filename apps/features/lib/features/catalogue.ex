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
    King,
    Lines,
    Material,
    Mobility,
    Motifs,
    Pawns,
    Placement,
    Space,
    Squares,
    State,
    Tactics,
    Threats
  }

  alias Features.Feature

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
    Motifs
  ]

  @doc "All features, in section order."
  @spec all() :: [Feature.t()]
  def all do
    Enum.flat_map(@sections, & &1.features())
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
