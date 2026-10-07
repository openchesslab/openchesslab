defmodule Analysis.PositionQuery do
  @moduledoc """
  Builds queries over canonical chess positions.

  The query language describes chess-position predicates independently
  of the persistence engine that executes them.
  """

  alias Chess.PawnStructure
  alias Chess.Position

  @type t ::
          true
          | false
          | {:property, atom(), term()}
          | {:equivalent, term()}
          | {:and, [t()]}
          | {:or, [t()]}
          | {:not, t()}

  @spec property(atom(), term()) :: t()
  def property(property, value) do
    {:property, property, value}
  end

  @spec pawn_structure(
          Position.t()
          | PawnStructure.t()
        ) ::
          t()
  def pawn_structure(%Position{} = position) do
    property(
      :pawn_structure,
      PawnStructure.from_position(position)
    )
  end

  def pawn_structure(%PawnStructure{} = structure) do
    property(
      :pawn_structure,
      structure
    )
  end

  @spec color_reversed_pawn_structure(
          Position.t()
          | PawnStructure.t()
        ) ::
          t()
  def color_reversed_pawn_structure(%Position{} = position) do
    position
    |> PawnStructure.from_position()
    |> color_reversed_pawn_structure()
  end

  def color_reversed_pawn_structure(%PawnStructure{} = structure) do
    structure
    |> PawnStructure.color_reversed()
    |> pawn_structure()
  end

  @spec equivalent(term()) :: t()
  def equivalent(position) do
    {:equivalent, position}
  end

  @spec all([t()]) :: t()
  def all(queries) do
    {:and, queries}
  end

  @spec any([t()]) :: t()
  def any(queries) do
    {:or, queries}
  end

  @spec negate(t()) :: t()
  def negate(query) do
    {:not, query}
  end

  @spec match_all() :: t()
  def match_all do
    true
  end

  @spec match_none() :: t()
  def match_none do
    false
  end
end
