defmodule PositionDBTest do
  use ExUnit.Case, async: true

  alias Chess.Position
  alias Chess.PositionCanonicalizer
  alias Chess.PositionKey
  alias Chess.PositionProperties
  alias Chess.PositionTransform
  alias Chess.Square
  alias PositionDB
  alias PositionDB.PositionIndexer
  alias PositionDB.PositionStore
  alias PositionDB.PropertyIndex
  alias PositionDB.PropertyIndex.Memory, as: PropertyIndexMemory
  alias PositionDB.Query

  defmodule FailingPropertyIndex do
    @behaviour PositionDB.PropertyIndex.Backend

    @impl PositionDB.PropertyIndex.Backend
    def add(
          %{fail_on: :add},
          _property,
          _position_id
        ) do
      {:error, :disk_failure}
    end

    def add(
          state,
          _property,
          _position_id
        ) do
      {:ok, state}
    end

    @impl PositionDB.PropertyIndex.Backend
    def advance(
          %{fail_on: :advance},
          _position_id
        ) do
      {:error, :disk_failure}
    end

    def advance(
          state,
          _position_id
        ) do
      {:ok, state}
    end

    @impl PositionDB.PropertyIndex.Backend
    def lookup(
          _state,
          _property
        ) do
      {:ok, []}
    end

    @impl PositionDB.PropertyIndex.Backend
    def cardinality(
          _state,
          _property
        ) do
      {:ok, 0}
    end
  end

  defmodule TrackingPropertyIndex do
    @behaviour PositionDB.PropertyIndex.Backend

    @impl PositionDB.PropertyIndex.Backend
    def add(
          state,
          property,
          position_id
        ) do
      send(
        state.test_pid,
        {:property_add, property, position_id}
      )

      {:ok, state}
    end

    @impl PositionDB.PropertyIndex.Backend
    def advance(
          state,
          position_id
        ) do
      send(
        state.test_pid,
        {:property_advance, position_id}
      )

      {:ok, state}
    end

    @impl PositionDB.PropertyIndex.Backend
    def lookup(
          _state,
          _property
        ) do
      {:ok, []}
    end

    @impl PositionDB.PropertyIndex.Backend
    def cardinality(
          _state,
          _property
        ) do
      {:ok, 0}
    end
  end

  defp new_db do
    PositionDB.new(
      key_function: & &1,
      properties: [
        {:open_files, & &1.open_files}
      ],
      equivalence_function: & &1.open_files,
      matcher: fn left, right ->
        left.open_files == right.open_files
      end
    )
  end

  test "stores and indexes a chess position" do
    position =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("a4"),
        {:white, :pawn}
      )

    db =
      PositionDB.new(
        key_function: &PositionKey.exact/1,
        properties: [
          {:open_files, &PositionProperties.open_files/1}
        ]
      )

    {db, position_id} = PositionDB.append(db, position)

    assert PositionDB.get(db, position_id) == {:ok, position}
    assert PositionDB.find(db, position) == {:ok, position_id}

    result =
      PositionDB.query(
        db,
        Query.property(:open_files, :e)
      )

    assert Enum.to_list(result) == [position_id]
  end

  test "uses a supplied storage backend" do
    storage =
      PositionDB.Storage.Memory.new()

    db =
      PositionDB.new(
        key_function: & &1,
        properties: [],
        storage: {
          PositionDB.Storage.Memory,
          storage
        }
      )

    assert db.store.storage_module ==
             PositionDB.Storage.Memory

    assert db.store.storage ==
             storage
  end

  test "appends through a supplied storage backend" do
    storage =
      PositionDB.Storage.Memory.new()

    db =
      PositionDB.new(
        key_function: & &1,
        properties: [],
        storage: {
          PositionDB.Storage.Memory,
          storage
        }
      )

    {db, position_id} =
      PositionDB.append(
        db,
        :position
      )

    assert position_id == 1

    assert PositionDB.get(
             db,
             position_id
           ) ==
             {:ok, :position}
  end

  test "stores an identical position only once" do
    position =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("a4"),
        {:white, :pawn}
      )

    db =
      PositionDB.new(
        key_function: &PositionKey.exact/1,
        properties: [
          {:open_files, &PositionProperties.open_files/1}
        ]
      )

    {db, id_1} = PositionDB.append(db, position)
    {db, id_2} = PositionDB.append(db, position)

    assert id_1 == id_2

    result =
      PositionDB.query(
        db,
        Query.property(:open_files, :e)
      )

    assert Enum.to_list(result) == [id_1]
  end

  test "different positions get different ids" do
    position_1 = Position.starting_position()

    position_2 =
      position_1
      |> Position.put_piece(
        Square.from_algebraic("a3"),
        {:white, :pawn}
      )

    db =
      PositionDB.new(
        key_function: &PositionKey.exact/1,
        properties: [
          {:open_files, &PositionProperties.open_files/1}
        ]
      )

    {db, id_1} = PositionDB.append(db, position_1)
    {_db, id_2} = PositionDB.append(db, position_2)

    assert id_1 != id_2
  end

  test "queries positions by property" do
    position =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("a4"),
        {:white, :pawn}
      )

    db =
      PositionDB.new(
        key_function: &PositionKey.exact/1,
        properties: [
          {:open_files, &PositionProperties.open_files/1}
        ]
      )

    {db, position_id} = PositionDB.append(db, position)

    assert Enum.to_list(
             PositionDB.query(
               db,
               Query.property(:open_files, :e)
             )
           ) == [position_id]

    assert Enum.to_list(
             PositionDB.query(
               db,
               Query.property(:open_files, :a)
             )
           ) == []
  end

  test "queries multiple positions by property" do
    position_1 =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("a4"),
        {:white, :pawn}
      )

    position_2 =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("b4"),
        {:white, :pawn}
      )

    db =
      PositionDB.new(
        key_function: &PositionKey.exact/1,
        properties: [
          {:open_files, &PositionProperties.open_files/1}
        ]
      )

    {db, id_1} = PositionDB.append(db, position_1)
    {db, id_2} = PositionDB.append(db, position_2)

    result =
      PositionDB.query(
        db,
        Query.property(:open_files, :e)
      )

    assert Enum.to_list(result) == [id_1, id_2]
  end

  test "queries positions using AND" do
    position_1 =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("a4"),
        {:white, :pawn}
      )

    position_2 =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("b4"),
        {:white, :pawn}
      )

    position_3 =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("d4"),
        {:white, :pawn}
      )

    db =
      PositionDB.new(
        key_function: &PositionKey.exact/1,
        properties: [
          {:open_files, &PositionProperties.open_files/1}
        ]
      )

    {db, id_1} = PositionDB.append(db, position_1)
    {db, id_2} = PositionDB.append(db, position_2)
    {db, _id_3} = PositionDB.append(db, position_3)

    query =
      Query.all([
        Query.property(:open_files, :e),
        Query.property(:open_files, :d)
      ])

    result = PositionDB.query(db, query)

    assert Enum.to_list(result) == [id_1, id_2]
  end

  test "queries positions using OR" do
    position_1 =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("a4"),
        {:white, :pawn}
      )

    position_2 =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("b4"),
        {:white, :pawn}
      )

    position_3 =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("d4"),
        {:white, :pawn}
      )

    db =
      PositionDB.new(
        key_function: &PositionKey.exact/1,
        properties: [
          {:open_files, &PositionProperties.open_files/1}
        ]
      )

    {db, id_1} = PositionDB.append(db, position_1)
    {db, id_2} = PositionDB.append(db, position_2)
    {db, id_3} = PositionDB.append(db, position_3)

    query =
      Query.any([
        Query.property(:open_files, :e),
        Query.property(:open_files, :d)
      ])

    result = PositionDB.query(db, query)

    assert Enum.to_list(result) == [id_1, id_2, id_3]
  end

  test "queries positions using NOT" do
    position_1 =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("a4"),
        {:white, :pawn}
      )

    position_2 =
      position_1
      |> Position.put_piece(
        Square.from_algebraic("e4"),
        {:white, :pawn}
      )

    db =
      PositionDB.new(
        key_function: &PositionKey.exact/1,
        properties: [
          {:open_files, &PositionProperties.open_files/1}
        ]
      )

    {db, _id_1} = PositionDB.append(db, position_1)
    {db, id_2} = PositionDB.append(db, position_2)

    query = Query.negate(Query.property(:open_files, :e))

    result = PositionDB.query(db, query)

    assert Enum.to_list(result) == [id_2]
  end

  test "queries positions using AND with true" do
    position =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("a4"),
        {:white, :pawn}
      )

    db =
      PositionDB.new(
        key_function: &PositionKey.exact/1,
        properties: [
          {:open_files, &PositionProperties.open_files/1}
        ]
      )

    {db, position_id} = PositionDB.append(db, position)

    query =
      Query.all([
        Query.property(:open_files, :e),
        Query.match_all()
      ])

    result = PositionDB.query(db, query)

    assert Enum.to_list(result) == [position_id]
  end

  test "queries positions using OR with false" do
    position =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("a4"),
        {:white, :pawn}
      )

    db =
      PositionDB.new(
        key_function: &PositionKey.exact/1,
        properties: [
          {:open_files, &PositionProperties.open_files/1}
        ]
      )

    {db, position_id} = PositionDB.append(db, position)

    query =
      Query.any([
        Query.property(:open_files, :e),
        Query.match_none()
      ])

    result = PositionDB.query(db, query)

    assert Enum.to_list(result) == [position_id]
  end

  test "queries equivalent positions through the facade" do
    position =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("a4"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("e7"),
        {:black, :queen}
      )

    swapped = PositionTransform.swap_colors(position)

    db =
      PositionDB.new(
        key_function: &PositionKey.exact/1,
        equivalence_function: &PositionCanonicalizer.encode/1,
        matcher: fn query, candidate ->
          query == candidate ||
            PositionTransform.swap_colors(query) == candidate
        end,
        properties: [
          {:open_files, &PositionProperties.open_files/1}
        ]
      )

    {db, id_1} = PositionDB.append(db, position)
    {db, id_2} = PositionDB.append(db, swapped)

    result =
      PositionDB.query(
        db,
        Query.equivalent(position)
      )

    assert Enum.to_list(result) == [id_1, id_2]
  end

  test "combines property and equivalent queries through the facade" do
    position =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("a4"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("e7"),
        {:black, :queen}
      )

    swapped = PositionTransform.swap_colors(position)

    other =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("a4"),
        {:white, :pawn}
      )

    db =
      PositionDB.new(
        key_function: &PositionKey.exact/1,
        equivalence_function: &PositionCanonicalizer.encode/1,
        matcher: fn query, candidate ->
          query == candidate ||
            PositionTransform.swap_colors(query) == candidate
        end,
        properties: [
          {:open_files, &PositionProperties.open_files/1}
        ]
      )

    {db, id_1} = PositionDB.append(db, position)
    {db, id_2} = PositionDB.append(db, swapped)
    {db, _id_3} = PositionDB.append(db, other)

    result =
      PositionDB.query(
        db,
        Query.all([
          Query.equivalent(position),
          Query.property(:open_files, :e)
        ])
      )

    assert Enum.to_list(result) == [id_1, id_2]
  end

  test "put and get return the stored position" do
    db = new_db()
    position = %{id: :position_1, open_files: [:a, :e]}

    {db, position_id} = PositionDB.append(db, position)

    assert PositionDB.get(db, position_id) == {:ok, position}
  end

  test "find returns the ID of an existing exact position" do
    db = new_db()
    position = %{id: :position_1, open_files: [:a, :e]}

    {db, position_id} = PositionDB.append(db, position)

    assert PositionDB.find(db, position) == {:ok, position_id}
  end

  test "find returns not_found for an unknown position" do
    db = new_db()

    position = %{id: :position_1, open_files: [:a, :e]}

    assert PositionDB.find(db, position) == :not_found
  end

  test "exact identity is separate from equivalence" do
    db = new_db()

    position_1 = %{id: :position_1, open_files: [:a, :e]}
    position_2 = %{id: :position_2, open_files: [:a, :e]}

    {db, id_1} = PositionDB.append(db, position_1)
    {db, id_2} = PositionDB.append(db, position_2)

    assert id_1 != id_2

    assert PositionDB.find(db, position_1) == {:ok, id_1}
    assert PositionDB.find(db, position_2) == {:ok, id_2}

    assert Enum.to_list(
             PositionDB.query(
               db,
               Query.equivalent(position_1)
             )
           ) == [id_1, id_2]
  end

  test "put updates property and equivalence indexes" do
    db = new_db()

    position = %{id: :position_1, open_files: [:a, :e]}

    {db, position_id} = PositionDB.append(db, position)

    assert Enum.to_list(
             PositionDB.query(
               db,
               Query.property(:open_files, :a)
             )
           ) == [position_id]

    assert Enum.to_list(
             PositionDB.query(
               db,
               Query.equivalent(position)
             )
           ) == [position_id]
  end

  test "match_all returns all stored position IDs" do
    db = new_db()

    positions = [
      %{id: :position_1, open_files: [:a]},
      %{id: :position_2, open_files: [:e]},
      %{id: :position_3, open_files: [:a, :e]}
    ]

    {ids, db} =
      Enum.map_reduce(
        positions,
        db,
        fn position, db ->
          {db, position_id} = PositionDB.append(db, position)
          {position_id, db}
        end
      )

    assert Enum.to_list(
             PositionDB.query(
               db,
               Query.match_all()
             )
           ) == ids
  end

  test "does not index an exact duplicate again" do
    properties = [
      {:open_files, & &1.open_files}
    ]

    db =
      PositionDB.new(
        key_function: & &1.id,
        properties: properties
      )

    property_index =
      PropertyIndex.new(
        TrackingPropertyIndex,
        %{
          test_pid: self()
        }
      )

    db = %{
      db
      | indexer:
          PositionIndexer.new(
            properties,
            property_index
          )
    }

    position = %{
      id: :position_1,
      open_files: [:a, :e]
    }

    {db, position_id} =
      PositionDB.append(
        db,
        position
      )

    assert_receive {
      :property_add,
      {:open_files, :a},
      ^position_id
    }

    assert_receive {
      :property_add,
      {:open_files, :e},
      ^position_id
    }

    assert_receive {
      :property_advance,
      ^position_id
    }

    {db, duplicate_id} =
      PositionDB.append(
        db,
        position
      )

    assert duplicate_id ==
             position_id

    assert PositionStore.cardinality(db.store) ==
             1

    refute_receive {
      :property_add,
      _property,
      _position_id
    }

    refute_receive {
      :property_advance,
      _position_id
    }
  end

  test "uses a supplied property index" do
    property_index =
      PropertyIndex.new(
        PropertyIndexMemory,
        PropertyIndexMemory.new()
      )

    db =
      PositionDB.new(
        key_function: & &1,
        properties: [],
        property_index: property_index
      )

    assert db.indexer.index ==
             property_index
  end

  test "propagates property posting errors while appending" do
    property_index =
      PropertyIndex.new(
        FailingPropertyIndex,
        %{
          fail_on: :add
        }
      )

    db =
      PositionDB.new(
        key_function: & &1.id,
        properties: [
          {:open_files, & &1.open_files}
        ],
        property_index: property_index
      )

    position = %{
      id: :position_1,
      open_files: [:a]
    }

    assert PositionDB.append(
             db,
             position
           ) ==
             {:error, :disk_failure}
  end

  test "propagates property progress errors while appending" do
    property_index =
      PropertyIndex.new(
        FailingPropertyIndex,
        %{
          fail_on: :advance
        }
      )

    db =
      PositionDB.new(
        key_function: & &1.id,
        properties: [
          {:open_files, & &1.open_files}
        ],
        property_index: property_index
      )

    position = %{
      id: :position_1,
      open_files: [:a]
    }

    assert PositionDB.append(
             db,
             position
           ) ==
             {:error, :disk_failure}
  end
end
