defmodule PositionDBTest do
  use ExUnit.Case, async: true

  alias Chess.PositionTransform
  alias Chess.PositionCanonicalizer
  alias Chess.Position
  alias Chess.PositionKey
  alias Chess.PositionProperties
  alias Chess.Square

  alias PositionDB.PropertyIndex

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

    {db, position_id} = PositionDB.put(db, position)

    assert PositionDB.get(db, position_id) == {:ok, position}
    assert PositionDB.find(db, position) == {:ok, position_id}

    assert PropertyIndex.lookup(
             db.indexer.index,
             {:open_files, :e}
           ) == MapSet.new([position_id])
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

    {db, id_1} = PositionDB.put(db, position)
    {db, id_2} = PositionDB.put(db, position)

    assert id_1 == id_2

    assert PositionDB.find_by_property(db, :open_files, :e) ==
             MapSet.new([id_1])

    query =
      {:property, :open_files, :e}

    assert Enum.to_list(PositionDB.query(db, query)) == [id_1]
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

    {db, id_1} = PositionDB.put(db, position_1)
    {_db, id_2} = PositionDB.put(db, position_2)

    assert id_1 != id_2
  end

  test "finds positions by property" do
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

    {db, position_id} = PositionDB.put(db, position)

    assert PositionDB.find_by_property(db, :open_files, :e) ==
             MapSet.new([position_id])

    assert PositionDB.find_by_property(db, :open_files, :a) ==
             MapSet.new()
  end

  test "finds multiple positions by property" do
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

    {db, id_1} = PositionDB.put(db, position_1)
    {db, id_2} = PositionDB.put(db, position_2)

    assert PositionDB.find_by_property(db, :open_files, :e) ==
             MapSet.new([id_1, id_2])
  end

  test "queries positions using multiple properties" do
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

    {db, id_1} = PositionDB.put(db, position_1)
    {db, id_2} = PositionDB.put(db, position_2)
    {db, _id_3} = PositionDB.put(db, position_3)

    query =
      {:and,
       [
         {:property, :open_files, :e},
         {:property, :open_files, :d}
       ]}

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

    {db, id_1} = PositionDB.put(db, position_1)
    {db, id_2} = PositionDB.put(db, position_2)
    {db, id_3} = PositionDB.put(db, position_3)

    query =
      {:or,
       [
         {:property, :open_files, :e},
         {:property, :open_files, :d}
       ]}

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

    {db, _id_1} = PositionDB.put(db, position_1)
    {db, id_2} = PositionDB.put(db, position_2)

    query =
      {:not, {:property, :open_files, :e}}

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

    {db, position_id} = PositionDB.put(db, position)

    query =
      {:and,
       [
         {:property, :open_files, :e},
         true
       ]}

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

    {db, position_id} = PositionDB.put(db, position)

    query =
      {:or,
       [
         {:property, :open_files, :e},
         false
       ]}

    result = PositionDB.query(db, query)

    assert Enum.to_list(result) == [position_id]
  end

  test "finds color-equivalent positions" do
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

    matcher = fn query, candidate ->
      query == candidate ||
        PositionTransform.swap_colors(query) == candidate
    end

    db =
      PositionDB.new(
        key_function: &PositionKey.exact/1,
        equivalence_function: &PositionCanonicalizer.encode/1,
        matcher: matcher,
        properties: [
          {:open_files, &PositionProperties.open_files/1}
        ]
      )

    {db, id_1} = PositionDB.put(db, position)
    {db, id_2} = PositionDB.put(db, swapped)

    assert id_1 != id_2

    assert PositionDB.find_equivalent(db, position) ==
             MapSet.new([id_1, id_2])

    assert PositionDB.find_equivalent(db, swapped) ==
             MapSet.new([id_1, id_2])
  end

  test "finds positions with the same equivalence key" do
    position =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("a4"),
        {:white, :pawn}
      )

    swapped = PositionTransform.swap_colors(position)

    db =
      PositionDB.new(
        key_function: &PositionKey.exact/1,
        equivalence_function: &PositionCanonicalizer.encode/1,
        properties: [
          {:open_files, &PositionProperties.open_files/1}
        ]
      )

    {db, id_1} = PositionDB.put(db, position)
    {db, id_2} = PositionDB.put(db, swapped)

    assert id_1 != id_2

    assert PositionDB.find_equivalent_candidates(db, position) ==
             MapSet.new([id_1, id_2])

    assert PositionDB.find_equivalent_candidates(db, swapped) ==
             MapSet.new([id_1, id_2])
  end

  test "queries through the PositionDB facade" do
    position =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("a4"),
        {:white, :pawn}
      )

    swapped =
      PositionTransform.swap_colors(position)

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

    {db, id_1} = PositionDB.put(db, position)
    {db, id_2} = PositionDB.put(db, swapped)

    result =
      PositionDB.query(
        db,
        {:equivalent, position}
      )

    assert Enum.to_list(result) == [id_1, id_2]
  end
end
