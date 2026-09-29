defmodule Analysis.PositionRecordCodec do
  @moduledoc """
  Adapts chess positions to the durable PositionDB record codec contract.
  """

  @behaviour PositionDB.Storage.RecordCodec

  alias Chess.Position
  alias Chess.PositionCodec
  alias PositionDB.Storage.RecordCodec

  @format_id <<"chess-position-v1">>

  @impl RecordCodec
  def format_id do
    @format_id
  end

  @impl RecordCodec
  def record_size do
    PositionCodec.record_size()
  end

  @impl RecordCodec
  def encode(%Position{} = position) do
    {:ok, PositionCodec.encode(position)}
  end

  def encode(_position) do
    {:error, :invalid_position}
  end

  @impl RecordCodec
  def decode(encoded) when is_binary(encoded) do
    PositionCodec.decode(encoded)
  end

  def decode(_encoded) do
    {:error, :invalid_record}
  end
end
