defmodule Analysis.PostgresPositionRepositoryTest do
  use ExUnit.Case, async: false

  alias Analysis.PositionRepository.Postgres, as: PositionRepository
  alias Chess.Position
  alias OpenChessLab.Repo

  @moduletag postgres: true

  setup_all do
    database_url =
      System.fetch_env!("DATABASE_URL")

    start_supervised!({
      Repo,
      url: database_url, pool_size: 1, log: false
    })

    Repo.query!(
      """
      SELECT 1
      FROM positions
      LIMIT 0
      """,
      []
    )

    :ok
  end

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

  test "stores a position and returns its durable id" do
    position =
      Position.starting_position()

    assert PositionRepository.put(position) ==
             {:ok, 1}

    assert PositionRepository.get(1) ==
             {:ok, position}
  end

  test "storing the same exact position reuses its id" do
    position =
      Position.starting_position()

    assert {:ok, position_id} =
             PositionRepository.put(position)

    assert PositionRepository.put(position) ==
             {:ok, position_id}

    assert [[1]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM positions
               """,
               []
             ).rows
  end

  test "finds an existing exact position" do
    position =
      Position.starting_position()

    assert {:ok, position_id} =
             PositionRepository.put(position)

    assert PositionRepository.find(position) ==
             {:ok, position_id}
  end

  test "returns not found for a position that is not stored" do
    assert PositionRepository.find(Position.new()) ==
             :not_found
  end

  test "returns not found for an unknown position id" do
    assert PositionRepository.get(999_999) ==
             :not_found
  end

  test "rejects position records with the wrong encoded size" do
    assert {:error, _reason} =
             Repo.query(
               """
               INSERT INTO positions (record)
               VALUES ($1)
               """,
               [
                 <<1, 2, 3>>
               ]
             )

    assert [[0]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM positions
               """,
               []
             ).rows
  end

  test "position features default to an empty property set" do
    assert {:ok, position_id} =
             Position.starting_position()
             |> PositionRepository.put()

    Repo.query!(
      """
      INSERT INTO position_features (position_id)
      VALUES ($1)
      """,
      [position_id]
    )

    assert [[[]]] =
             Repo.query!(
               """
               SELECT properties
               FROM position_features
               WHERE position_id = $1
               """,
               [position_id]
             ).rows
  end

  test "deleting a position cascades to its derived features" do
    assert {:ok, position_id} =
             Position.starting_position()
             |> PositionRepository.put()

    Repo.query!(
      """
      INSERT INTO position_features (
        position_id,
        properties
      )
      VALUES (
        $1,
        ARRAY[$2::bytea]::bytea[]
      )
      """,
      [
        position_id,
        <<1>>
      ]
    )

    Repo.query!(
      """
      DELETE FROM positions
      WHERE id = $1
      """,
      [position_id]
    )

    assert [[0]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM position_features
               """,
               []
             ).rows
  end
end
