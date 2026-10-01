defmodule Analysis.PositionRepository do
  @moduledoc """
  Persistence contract for canonical chess positions.

  Repository implementations own durable position identity, exact lookup,
  derived search features and bounded position queries.
  """

  alias Analysis.PositionQuery
  alias Chess.Position

  @type position_id :: pos_integer()
  @type query_cursor :: term()

  @callback ready?() :: boolean()

  @callback put(Position.t()) ::
              {:ok, position_id()}
              | {:error, term()}

  @callback get(position_id()) ::
              {:ok, Position.t()}
              | :not_found
              | {:error, term()}

  @callback find(Position.t()) ::
              {:ok, position_id()}
              | :not_found
              | {:error, term()}

  @callback query_page(
              PositionQuery.t(),
              pos_integer()
            ) ::
              {:ok, [position_id()], :done | query_cursor()}
              | {:error, term()}

  @callback next_query_page(
              query_cursor(),
              pos_integer()
            ) ::
              {:ok, [position_id()], :done | query_cursor()}
              | {:error, term()}

  @callback close_query(query_cursor()) :: :ok
end
