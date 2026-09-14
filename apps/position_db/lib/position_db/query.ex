defmodule PositionDB.Query do
  @moduledoc """
  Query representation for position searches.
  """

  @type t ::
          true
          | false
          | {:property, atom(), term()}
          | {:and, [t()]}
          | {:or, [t()]}
          | {:not, t()}
end
