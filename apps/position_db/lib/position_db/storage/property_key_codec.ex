defmodule PositionDB.Storage.PropertyKeyCodec do
  @moduledoc """
  Encodes logical property keys for durable secondary indexes.

  A codec defines one durable binary property-key format.
  Its format ID must change whenever the binary representation
  or property-key semantics change incompatibly.
  """

  @type property_name :: atom()
  @type property_value :: term()
  @type format_id :: binary()
  @type encoded_key :: binary()

  @callback format_id() :: format_id()

  @callback encode(
              property_name(),
              property_value()
            ) ::
              {:ok, encoded_key()}
              | {:error, term()}
end
