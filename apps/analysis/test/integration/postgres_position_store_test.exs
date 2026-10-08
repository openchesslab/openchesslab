defmodule Analysis.PostgresPositionStoreTest do
  use ExUnit.Case, async: false

  alias Analysis.PositionPropertyKeyCodec
  alias Analysis.PositionQuery, as: Query
  alias Analysis.PositionStore
  alias Chess.Move
  alias Chess.Position
  alias Chess.PositionProperties
  alias Chess.Square
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

  test "stores a position and returns its durable id" do
    position =
      Position.starting_position()

    assert PositionStore.append(position) ==
             1

    assert PositionStore.get(1) ==
             {:ok, position}
  end

  test "storing the same exact position reuses its id" do
    position =
      Position.starting_position()

    position_id =
      PositionStore.append(position)

    assert PositionStore.append(position) ==
             position_id

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

    position_id =
      PositionStore.append(position)

    assert PositionStore.find(position) ==
             {:ok, position_id}
  end

  test "returns not found for a position that is not stored" do
    assert PositionStore.find(Position.new()) ==
             :not_found
  end

  test "returns not found for an unknown position id" do
    assert PositionStore.get(999_999) ==
             :not_found
  end

  test "stores derived material properties" do
    position =
      Position.starting_position()

    position_id =
      PositionStore.append(position)

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

    assert Enum.count(
             properties,
             &(&1 == material_property)
           ) == 1
  end

  test "stores every open file as an independently searchable property" do
    empty_position =
      Position.new()

    position_id =
      PositionStore.append(empty_position)

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

    first_id =
      PositionStore.append(first)

    second_id =
      PositionStore.append(second)

    material =
      PositionProperties.material(first)

    assert {
             :ok,
             %PositionStore.Page{
               entries: position_ids,
               next: nil
             }
           } =
             PositionStore.page(
               Query.property(
                 :material,
                 material
               ),
               limit: 10
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

    starting_id =
      PositionStore.append(starting)

    empty_id =
      PositionStore.append(empty)

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
             %PositionStore.Page{
               entries: position_ids,
               next: nil
             }
           } =
             PositionStore.page(
               query,
               limit: 10
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
        &PositionStore.append/1
      )

    assert {
             :ok,
             %PositionStore.Page{
               entries: first_page,
               next: cursor
             }
           } =
             PositionStore.page(
               Query.match_all(),
               limit: 2
             )

    assert %PositionStore.Cursor{} =
             cursor

    assert {
             :ok,
             %PositionStore.Page{
               entries: second_page,
               next: nil
             }
           } =
             PositionStore.page(
               Query.match_all(),
               limit: 2,
               cursor: cursor
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

    first_id =
      PositionStore.append(first)

    second_id =
      PositionStore.append(second)

    assert {
             :ok,
             %PositionStore.Page{
               entries: [
                 ^first_id
               ],
               next: cursor
             }
           } =
             PositionStore.page(
               Query.match_all(),
               limit: 1
             )

    third_id =
      PositionStore.append(third)

    assert {
             :ok,
             %PositionStore.Page{
               entries: [
                 ^second_id
               ],
               next: nil
             }
           } =
             PositionStore.page(
               Query.match_all(),
               limit: 1,
               cursor: cursor
             )

    refute third_id in [
             first_id,
             second_id
           ]
  end

  test "returns an empty page for match none" do
    _position_id =
      PositionStore.append(Position.starting_position())

    assert PositionStore.page(
             Query.match_none(),
             limit: 10
           ) ==
             {
               :ok,
               %PositionStore.Page{
                 entries: [],
                 next: nil
               }
             }
  end

  test "requires a positive page limit" do
    assert PositionStore.page(
             Query.match_all(),
             []
           ) ==
             {:error, :missing_limit}

    assert PositionStore.page(
             Query.match_all(),
             limit: 0
           ) ==
             {:error, :invalid_limit}
  end

  test "rejects invalid cursors" do
    assert PositionStore.page(
             Query.match_all(),
             limit: 10,
             cursor: make_ref()
           ) ==
             {:error, :invalid_cursor}
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

  test "does not rewrite features when storing an existing exact position" do
    position =
      Position.starting_position()

    position_id =
      PositionStore.append(position)

    queries =
      capture_queries(fn ->
        assert PositionStore.append(position) ==
                 position_id
      end)

    refute Enum.any?(
             queries,
             &String.contains?(
               &1,
               "INSERT INTO position_features"
             )
           )
  end

  test "resolves an existing exact position without a separate lookup query" do
    position =
      Position.starting_position()

    position_id =
      PositionStore.append(position)

    queries =
      capture_queries(fn ->
        assert PositionStore.append(position) ==
                 position_id
      end)

    normalized_queries =
      Enum.map(
        queries,
        fn query ->
          query
          |> String.replace(
            ~r/\s+/,
            " "
          )
          |> String.trim()
        end
      )

    assert Enum.count(
             normalized_queries,
             &String.starts_with?(
               &1,
               "WITH inserted AS"
             )
           ) ==
             1

    refute Enum.any?(
             normalized_queries,
             &String.starts_with?(
               &1,
               "SELECT id FROM positions WHERE record = $1"
             )
           )
  end

  test "concurrent exact position stores reuse one canonical position" do
    position =
      Position.starting_position()

    tasks =
      Enum.map(
        1..10,
        fn _index ->
          Task.async(fn ->
            PositionStore.append(position)
          end)
        end
      )

    position_ids =
      Task.await_many(
        tasks,
        5_000
      )

    assert [
             position_id
           ] =
             Enum.uniq(position_ids)

    assert is_integer(position_id)
    assert position_id > 0

    assert [[1]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM positions
               """,
               []
             ).rows

    assert [[1]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM position_features
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

  defp capture_queries(fun) do
    telemetry_prefix =
      Repo.config()
      |> Keyword.fetch!(:telemetry_prefix)

    event =
      telemetry_prefix ++
        [:query]

    handler_id =
      {
        __MODULE__,
        make_ref()
      }

    parent =
      self()

    :ok =
      :telemetry.attach(
        handler_id,
        event,
        fn _event, _measurements, metadata, parent ->
          send(
            parent,
            {
              :captured_query,
              metadata.query
            }
          )
        end,
        parent
      )

    try do
      fun.()
      drain_queries([])
    after
      :telemetry.detach(handler_id)
    end
  end

  defp drain_queries(queries) do
    receive do
      {
        :captured_query,
        query
      } ->
        drain_queries([query | queries])
    after
      0 ->
        Enum.reverse(queries)
    end
  end
end
