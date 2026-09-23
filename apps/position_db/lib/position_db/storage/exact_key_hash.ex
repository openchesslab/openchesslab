defmodule PositionDB.Storage.ExactKeyHash do
  @moduledoc """
  Hashes exact position keys for durable exact-index storage.

  A hash implementation defines one durable hash format.
  Its format ID must change when the hash representation or
  exact-key hashing semantics change incompatibly.
  """

  @type key :: binary()
  @type format_id :: binary()
  @type hash :: binary()

  @callback format_id() :: format_id()

  @callback hash_size() :: pos_integer()

  @callback hash(key()) ::
              {:ok, hash()}
              | {:error, term()}
end
