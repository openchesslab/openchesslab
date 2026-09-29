defmodule GameDB.RecordCodec do
  @moduledoc """
  Converts canonical game records to and from their durable binary form.

  GameDB storage remains independent of the application-level game
  representation by depending only on this contract.
  """

  @type encoded :: binary()

  @callback encode(term()) ::
              {:ok, encoded()}
              | {:error, term()}

  @callback decode(encoded()) ::
              {:ok, term()}
              | {:error, term()}
end
