defmodule PositionDB.PropertyIndex.Backend do
  @moduledoc """
  Storage contract for logical property indexes.
  """

  @type t :: term()
  @type property :: {atom(), term()}
  @type position_id :: pos_integer()

  @callback add(
              t(),
              property(),
              position_id()
            ) ::
              {:ok, t()}
              | {:error, term()}

  @callback advance(
              t(),
              position_id()
            ) ::
              {:ok, t()}
              | {:error, term()}

  @callback lookup(
              t(),
              property()
            ) ::
              {:ok, [position_id()]}
              | {:error, term()}

  @callback cardinality(
              t(),
              property()
            ) ::
              {:ok, non_neg_integer()}
              | {:error, term()}
end
