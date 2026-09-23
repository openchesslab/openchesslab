defmodule Analysis.PositionExactKeyHash do
  @moduledoc """
  Adapts chess exact-position keys to the durable PositionDB
  exact-key hash contract.
  """

  @behaviour PositionDB.Storage.ExactKeyHash

  alias Chess.PositionHash

  @format_id <<"chess-position-exact-sha256-v1">>
  @hash_size 32

  @impl PositionDB.Storage.ExactKeyHash
  def format_id do
    @format_id
  end

  @impl PositionDB.Storage.ExactKeyHash
  def hash_size do
    @hash_size
  end

  @impl PositionDB.Storage.ExactKeyHash
  def hash(key)
      when is_binary(key) do
    {:ok, PositionHash.hash(key)}
  end

  def hash(_key) do
    {:error, :invalid_exact_key}
  end
end
