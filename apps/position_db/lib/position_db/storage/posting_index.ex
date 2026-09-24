defmodule PositionDB.Storage.PostingIndex do
  @moduledoc """
  Storage contract for secondary posting indexes.

  A posting index maps a stable encoded binary key to the
  position IDs that contain that key.

  Lookup results are returned in ascending position ID order
  so they can be consumed directly by query executors.
  """

  @type t :: term()
  @type key :: binary()
  @type position_id :: pos_integer()

  @callback add(
              t(),
              key(),
              position_id()
            ) ::
              {:ok, t()}
              | {:error, term()}

  @callback lookup(
              t(),
              key()
            ) ::
              {:ok, [position_id()]}
              | {:error, term()}

  @callback cardinality(
              t(),
              key()
            ) ::
              {:ok, non_neg_integer()}
              | {:error, term()}
end
