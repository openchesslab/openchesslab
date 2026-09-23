defmodule PositionDB.Storage.RecordCodec do
  @moduledoc """
  Converts logical positions to and from fixed-size durable records.

  A codec defines one physical record format. Its format ID must
  change when the binary representation changes incompatibly.
  """

  @type position :: term()
  @type format_id :: binary()
  @type encoded_record :: binary()

  @callback format_id() :: format_id()

  @callback record_size() :: pos_integer()

  @callback encode(position()) ::
              {:ok, encoded_record()}
              | {:error, term()}

  @callback decode(encoded_record()) ::
              {:ok, position()}
              | {:error, term()}
end
