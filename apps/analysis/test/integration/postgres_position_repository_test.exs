defmodule Analysis.PostgresPositionRepositoryTest do
  use ExUnit.Case, async: false

  alias Analysis.PositionPropertyKeyCodec
  alias Analysis.PositionRepository.Postgres, as: PositionRepository
  alias Chess.Move
  alias Chess.Position
  alias Chess.PositionProperties
  alias Chess.Square
  alias OpenChessLab.Repo
  alias PositionDB.Query

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

  test "stores derived open-file and material properties" do
    position =
      Position.starting_position()

    assert {:ok, position_id} =
             PositionRepository.put(position)

    assert [[properties]] =
             Repo.query!(
               """
               SELECT properties
               FROM position_features
               WHERE position_id = $1
               """,
               [position_id]
             ).rows

    {:ok, material_property} =
      PositionPropertyKeyCodec.encode(
        :material,
        PositionProperties.material(position)
      )

    assert material_property in properties

    assert length(properties) == 1
  end

  test "stores every open file as an independently searchable property" do
    position =
      Position.new(
        board: Position.starting_position().board,
        side_to_move: :white
      )

    empty_position =
      Position.new()

    assert {:ok, position_id} =
             PositionRepository.put(empty_position)

    assert [[properties]] =
             Repo.query!(
               """
               SELECT properties
               FROM position_features
               WHERE position_id = $1
               """,
               [position_id]
             ).rows

    expected_open_files =
      Enum.map(
        PositionProperties.open_files(empty_position),
        fn file ->
          {:ok, encoded} =
            PositionPropertyKeyCodec.encode(
              :open_files,
              file
            )

          encoded
        end
      )

    assert Enum.all?(
             expected_open_files,
             &(&1 in properties)
           )

    assert position != empty_position
  end

  test "queries matching positions by material" do
    first =
      Position.starting_position()

    {:ok, second} =
      Position.apply_move(
        first,
        move(
          "e2",
          "e4"
        )
      )

    assert {:ok, first_id} =
             PositionRepository.put(first)

    assert {:ok, second_id} =
             PositionRepository.put(second)

    material =
      PositionProperties.material(first)

    assert {
             :ok,
             position_ids,
             :done
           } =
             PositionRepository.query_page(
               Query.property(
                 :material,
                 material
               ),
               10
             )

    assert position_ids ==
             [
               first_id,
               second_id
             ]
  end

  test "supports boolean property queries" do
    starting =
      Position.starting_position()

    empty =
      Position.new()

    assert {:ok, starting_id} =
             PositionRepository.put(starting)

    assert {:ok, empty_id} =
             PositionRepository.put(empty)

    starting_material =
      PositionProperties.material(starting)

    query =
      Query.any([
        Query.property(
          :material,
          starting_material
        ),
        Query.property(
          :open_files,
          :a
        )
      ])

    assert {
             :ok,
             position_ids,
             :done
           } =
             PositionRepository.query_page(
               query,
               10
             )

    assert MapSet.new(position_ids) ==
             MapSet.new([
               starting_id,
               empty_id
             ])
  end

  test "pages queries without duplicates or omissions" do
    first =
      Position.starting_position()

    {:ok, second} =
      Position.apply_move(
        first,
        move(
          "e2",
          "e4"
        )
      )

    {:ok, third} =
      Position.apply_move(
        second,
        move(
          "e7",
          "e5"
        )
      )

    ids =
      Enum.map(
        [
          first,
          second,
          third
        ],
        fn position ->
          {:ok, position_id} =
            PositionRepository.put(position)

          position_id
        end
      )

    assert {
             :ok,
             first_page,
             cursor
           } =
             PositionRepository.query_page(
               Query.match_all(),
               2
             )

    assert {
             :ok,
             second_page,
             :done
           } =
             PositionRepository.next_query_page(
               cursor,
               2
             )

    assert first_page ++ second_page ==
             ids
  end

  test "does not include positions added after a query starts" do
    first =
      Position.starting_position()

    {:ok, second} =
      Position.apply_move(
        first,
        move(
          "e2",
          "e4"
        )
      )

    {:ok, third} =
      Position.apply_move(
        second,
        move(
          "e7",
          "e5"
        )
      )

    assert {:ok, first_id} =
             PositionRepository.put(first)

    assert {:ok, second_id} =
             PositionRepository.put(second)

    assert {
             :ok,
             [^first_id],
             cursor
           } =
             PositionRepository.query_page(
               Query.match_all(),
               1
             )

    assert {:ok, third_id} =
             PositionRepository.put(third)

    assert {
             :ok,
             [^second_id],
             :done
           } =
             PositionRepository.next_query_page(
               cursor,
               1
             )

    refute third_id in [
             first_id,
             second_id
           ]
  end

  test "returns an empty page for match none" do
    assert {:ok, _position_id} =
             PositionRepository.put(Position.starting_position())

    assert PositionRepository.query_page(
             Query.match_none(),
             10
           ) ==
             {
               :ok,
               [],
               :done
             }
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

  defp move(from, to) do
    Move.new(
      Square.from_algebraic(from),
      Square.from_algebraic(to)
    )
  end
end
