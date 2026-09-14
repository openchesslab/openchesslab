defmodule PositionDBTest do
  use ExUnit.Case, async: true

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
    position = Position.starting_position()

    db =
      PositionDB.new(
        key_function: &PositionKey.exact/1,
        properties: [
          {:open_files, &PositionProperties.open_files/1}
        ]
      )

    {db, id_1} = PositionDB.put(db, position)
    {_db, id_2} = PositionDB.put(db, position)

    assert id_1 == id_2
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
end
