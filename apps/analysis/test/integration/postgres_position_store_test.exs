defmodule Analysis.PostgresPositionStoreTest do
  use ExUnit.Case, async: false

  alias Analysis.PositionQuery, as: Query
  alias Analysis.PositionRepository.Postgres
  alias Analysis.PositionStore
  alias Chess.Position
  alias OpenChessLab.Repo

  @moduletag postgres: true

  setup do
    Repo.query!(
      """
      TRUNCATE TABLE
        position_features,
        positions
      RESTART IDENTITY
      CASCADE
      """,
      []
    )

    :ok
  end

  test "uses PostgreSQL as the default position repository" do
    assert PositionStore.repository() ==
             Postgres
  end

  test "appends, gets and finds positions without a position store process" do
    position =
      Position.starting_position()

    position_id =
      PositionStore.append(position)

    assert position_id == 1

    assert PositionStore.get(position_id) ==
             {:ok, position}

    assert PositionStore.find(position) ==
             {:ok, position_id}

    assert PositionStore.ready?()
  end

  test "queries PostgreSQL directly through the position store facade" do
    first_id =
      PositionStore.append(Position.starting_position())

    second_id =
      PositionStore.append(Position.new())

    assert {
             :ok,
             [
               ^first_id
             ],
             cursor
           } =
             PositionStore.query_page(
               Query.match_all(),
               1
             )

    assert %Postgres.Cursor{} =
             cursor

    assert {
             :ok,
             [
               ^second_id
             ],
             :done
           } =
             PositionStore.next_query_page(
               cursor,
               1
             )

    assert :ok =
             PositionStore.close_query(cursor)
  end
end
