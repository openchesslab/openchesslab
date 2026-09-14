defmodule PositionDB.Query do
  @moduledoc """
  Query representation for position searches.
  """

  @type t ::
          {:property, atom(), term()}
          | {:and, [t()]}
          | {:or, [t()]}
          | {:not, t()}
end
