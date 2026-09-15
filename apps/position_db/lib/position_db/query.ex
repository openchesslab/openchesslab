defmodule PositionDB.Query do
  @moduledoc """
  Query representation for position searches.
  """

  @type t ::
          true
          | false
          | {:property, atom(), term()}
          | {:equivalent, term()}
          | {:and, [t()]}
          | {:or, [t()]}
          | {:not, t()}
end
