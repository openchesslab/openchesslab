defmodule PositionDB.Storage.ExactIndex do
  @moduledoc """
  Indexes exact position keys to candidate position IDs.

  Keys are not assumed to be unique. Lookup therefore returns
  candidate IDs whose full records must still be compared by
  the storage implementation.
  """

  @type t :: term()
  @type key :: binary()
  @type position_id :: pos_integer()

  @callback add(t(), key(), position_id()) ::
              {:ok, t()} | {:error, term()}

  @callback lookup(t(), key()) ::
              {:ok, [position_id()]} | {:error, term()}
end
