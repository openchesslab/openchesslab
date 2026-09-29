defmodule GameDB.RecordCodec do
  @moduledoc """
  Converts canonical game records to and from their durable binary form.

  GameDB storage remains independent of the application-level game
  representation by depending only on this contract.

  A codec's format ID must change whenever its durable binary
  representation changes incompatibly.
  """

  @type format_id :: binary()
  @type encoded :: binary()

  @callback format_id() :: format_id()

  @callback encode(term()) ::
              {:ok, encoded()}
              | {:error, term()}

  @callback decode(encoded()) ::
              {:ok, term()}
              | {:error, term()}
end
