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
          | {:pawn_structures, [PawnStructure.t()]}
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

  @spec pawn_structures([PawnStructure.t()]) :: t()
  def pawn_structures(structures) when is_list(structures) do
    {
      :pawn_structures,
      structures
    }
  end

  @spec pawn_structure_symmetries(
          Position.t()
          | PawnStructure.t()
        ) ::
          t()
  def pawn_structure_symmetries(%Position{} = position) do
    position
    |> PawnStructure.from_position()
    |> pawn_structure_symmetries()
  end

  def pawn_structure_symmetries(%PawnStructure{} = structure) do
    structure
    |> PawnStructure.symmetries()
    |> pawn_structures()
  end

  @doc """
  Searches the exact pawn structure together with every structure that
  differs by one single-rank pawn displacement.

  The neighborhood is direction-independent: if one structure can be
  reached from the other through one forward structural pawn shift, each
  structure is in the other's neighborhood.
  """
  @spec pawn_structure_single_push_neighborhood(
          Position.t()
          | PawnStructure.t()
        ) ::
          t()
  def pawn_structure_single_push_neighborhood(%Position{} = position) do
    position
    |> PawnStructure.from_position()
    |> pawn_structure_single_push_neighborhood()
  end

  def pawn_structure_single_push_neighborhood(%PawnStructure{} = structure) do
    [
      structure
      | PawnStructure.single_rank_neighbors(structure)
    ]
    |> pawn_structures()
  end

  @doc """
  Searches the exact pawn structure together with every structure differing
  by one capture-like pawn displacement.

  A capture-like displacement moves exactly one pawn by one file and one
  rank diagonally. The neighborhood is direction-independent and may
  therefore represent either the creation or removal of a doubled-pawn
  structure.

  This models structural similarity rather than legal chess captures.
  """
  @spec pawn_structure_single_capture_like_neighborhood(
          Position.t()
          | PawnStructure.t()
        ) ::
          t()
  def pawn_structure_single_capture_like_neighborhood(%Position{} = position) do
    position
    |> PawnStructure.from_position()
    |> pawn_structure_single_capture_like_neighborhood()
  end

  def pawn_structure_single_capture_like_neighborhood(%PawnStructure{} = structure) do
    [
      structure
      | PawnStructure.single_capture_like_neighbors(structure)
    ]
    |> pawn_structures()
  end

  @doc """
  Searches the exact pawn structure together with every structure obtained
  by removing exactly one pawn.

  The relationship is directional. A query built from a structure containing
  a pawn will find the otherwise-identical structure without that pawn. A query
  built from the reduced structure does not implicitly add the missing pawn.
  """
  @spec pawn_structure_missing_pawn_neighborhood(
          Position.t()
          | PawnStructure.t()
        ) ::
          t()
  def pawn_structure_missing_pawn_neighborhood(%Position{} = position) do
    position
    |> PawnStructure.from_position()
    |> pawn_structure_missing_pawn_neighborhood()
  end

  def pawn_structure_missing_pawn_neighborhood(%PawnStructure{} = structure) do
    [
      structure
      | PawnStructure.single_pawn_removals(structure)
    ]
    |> pawn_structures()
  end

  @doc """
  Searches the exact pawn structure and every direction-independent
  single-push neighbor under every supported pawn-structure symmetry.

  The bounded set contains the symmetries of:

    * the exact structure
    * every structure differing by one single-rank pawn displacement

  Duplicate structures are removed before constructing the query.
  """
  @spec pawn_structure_single_push_symmetry_neighborhood(
          Position.t()
          | PawnStructure.t()
        ) ::
          t()
  def pawn_structure_single_push_symmetry_neighborhood(%Position{} = position) do
    position
    |> PawnStructure.from_position()
    |> pawn_structure_single_push_symmetry_neighborhood()
  end

  def pawn_structure_single_push_symmetry_neighborhood(%PawnStructure{} = structure) do
    [
      structure
      | PawnStructure.single_rank_neighbors(structure)
    ]
    |> Enum.flat_map(&PawnStructure.symmetries/1)
    |> Enum.uniq()
    |> pawn_structures()
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

  @spec file_reflected_pawn_structure(
          Position.t()
          | PawnStructure.t()
        ) ::
          t()
  def file_reflected_pawn_structure(%Position{} = position) do
    position
    |> PawnStructure.from_position()
    |> file_reflected_pawn_structure()
  end

  def file_reflected_pawn_structure(%PawnStructure{} = structure) do
    structure
    |> PawnStructure.file_reflected()
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
