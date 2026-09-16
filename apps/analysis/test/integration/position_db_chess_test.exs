defmodule PositionDB.PositionDbChessTest do
  use ExUnit.Case, async: true

  alias Chess.Position
  alias Chess.PositionKey
  alias Chess.PositionProperties
  alias Chess.PositionTransform
  alias Chess.Square

  alias PositionDB
  alias PositionDB.Query

  defp new_db do
    PositionDB.new(
      key_function: &PositionKey.exact/1,
      equivalence_function: &PositionKey.equivalent(&1, :color_swap),
      matcher: fn query, candidate ->
        PositionKey.equivalent(query, :color_swap) ==
          PositionKey.equivalent(candidate, :color_swap)
      end,
      properties: [
        {:open_files, &PositionProperties.open_files/1},
        {:material, &PositionProperties.material/1}
      ]
    )
  end

  test "stores and retrieves a real Chess.Position exactly" do
    position =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("a4"),
        {:white, :pawn}
      )

    db = new_db()

    {db, position_id} = PositionDB.put(db, position)

    assert PositionDB.get(db, position_id) == {:ok, position}
    assert PositionDB.find(db, position) == {:ok, position_id}
  end

  test "color-swapped positions have different exact IDs but are equivalent" do
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

    db = new_db()

    {db, id_1} = PositionDB.put(db, position)
    {db, id_2} = PositionDB.put(db, swapped)

    assert id_1 != id_2

    assert PositionDB.find(db, position) == {:ok, id_1}
    assert PositionDB.find(db, swapped) == {:ok, id_2}

    assert Enum.to_list(
             PositionDB.query(
               db,
               Query.equivalent(position)
             )
           ) == [id_1, id_2]
  end

  test "queries a real Chess.Position property" do
    position_1 =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("a4"),
        {:white, :pawn}
      )

    position_2 =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("e4"),
        {:white, :pawn}
      )

    db = new_db()

    {db, id_1} = PositionDB.put(db, position_1)
    {db, _id_2} = PositionDB.put(db, position_2)

    assert :e in PositionProperties.open_files(position_1)
    assert :a in PositionProperties.open_files(position_2)

    assert Enum.to_list(
             PositionDB.query(
               db,
               Query.property(:open_files, :e)
             )
           ) == [id_1]
  end

  test "queries a real Chess.Position using multiple properties" do
    position_1 =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("a4"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("b4"),
        {:black, :pawn}
      )

    position_2 =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("a4"),
        {:white, :pawn}
      )

    position_3 =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("a4"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("e4"),
        {:black, :pawn}
      )

    db = new_db()

    {db, id_1} = PositionDB.put(db, position_1)
    {db, id_2} = PositionDB.put(db, position_2)
    {db, id_3} = PositionDB.put(db, position_3)

    material_1 = PositionProperties.material(position_1)

    assert Enum.to_list(
             PositionDB.query(
               db,
               Query.property(:open_files, :e)
             )
           ) == [id_1, id_2]

    assert Enum.to_list(
             PositionDB.query(
               db,
               Query.property(:material, material_1)
             )
           ) == [id_1, id_3]

    assert Enum.to_list(
             PositionDB.query(
               db,
               Query.all([
                 Query.property(:open_files, :e),
                 Query.property(:material, material_1)
               ])
             )
           ) == [id_1]
  end
end
