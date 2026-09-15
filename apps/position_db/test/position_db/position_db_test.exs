defmodule PositionDBTest do
  use ExUnit.Case, async: true

  alias Chess.Position
  alias Chess.PositionCanonicalizer
  alias Chess.PositionKey
  alias Chess.PositionProperties
  alias Chess.PositionTransform
  alias Chess.Square

  alias PositionDB.Query

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

    result =
      PositionDB.query(
        db,
        Query.property(:open_files, :e)
      )

    assert Enum.to_list(result) == [position_id]
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

    {db, id_1} = PositionDB.put(db, position_1)
    {_db, id_2} = PositionDB.put(db, position_2)

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

    {db, position_id} = PositionDB.put(db, position)

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

    {db, id_1} = PositionDB.put(db, position_1)
    {db, id_2} = PositionDB.put(db, position_2)

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

    {db, id_1} = PositionDB.put(db, position_1)
    {db, id_2} = PositionDB.put(db, position_2)
    {db, _id_3} = PositionDB.put(db, position_3)

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

    {db, id_1} = PositionDB.put(db, position_1)
    {db, id_2} = PositionDB.put(db, position_2)
    {db, id_3} = PositionDB.put(db, position_3)

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

    {db, _id_1} = PositionDB.put(db, position_1)
    {db, id_2} = PositionDB.put(db, position_2)

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

    {db, position_id} = PositionDB.put(db, position)

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

    {db, position_id} = PositionDB.put(db, position)

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

    {db, id_1} = PositionDB.put(db, position)
    {db, id_2} = PositionDB.put(db, swapped)

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

    {db, id_1} = PositionDB.put(db, position)
    {db, id_2} = PositionDB.put(db, swapped)
    {db, _id_3} = PositionDB.put(db, other)

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
end
