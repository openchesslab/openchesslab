defmodule Analysis.PositionQuery do
  @moduledoc """
  Builds queries over canonical chess positions.

  The query language describes chess-position predicates independently
  of the persistence engine that executes them.
  """

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
