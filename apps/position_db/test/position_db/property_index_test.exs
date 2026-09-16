defmodule PositionDB.PropertyIndexTest do
  use ExUnit.Case

  alias Chess.Position
  alias Chess.PositionProperties
  alias PositionDB.PositionIndexer
  alias PositionDB.PropertyIndex

  test "adds and finds a position" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 42)

    assert PropertyIndex.lookup(index, {:open_files, :e}) ==
             MapSet.new([42])
  end

  test "multiple positions can have the same property" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 42)
      |> PropertyIndex.add({:open_files, :e}, 91)

    assert PropertyIndex.lookup(index, {:open_files, :e}) ==
             MapSet.new([42, 91])
  end

  test "adding the same position twice does not duplicate it" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 42)
      |> PropertyIndex.add({:open_files, :e}, 42)

    assert PropertyIndex.lookup(index, {:open_files, :e}) ==
             MapSet.new([42])
  end

  test "unknown property returns empty set" do
    assert PropertyIndex.lookup(PropertyIndex.new(), {:open_files, :e}) ==
             MapSet.new()
  end

  test "indexes configured position properties" do
    indexer =
      PositionIndexer.new([
        {:open_files, &PositionProperties.open_files/1}
      ])

    position_1 =
      Position.new()
      |> Position.put_piece(Chess.Square.from_algebraic("a4"), {:white, :pawn})

    position_2 =
      Position.new()
      |> Position.put_piece(Chess.Square.from_algebraic("b4"), {:white, :pawn})

    position_3 =
      Position.new()
      |> Position.put_piece(Chess.Square.from_algebraic("a5"), {:black, :pawn})

    indexer =
      indexer
      |> PositionIndexer.index(1, position_1)
      |> PositionIndexer.index(2, position_2)
      |> PositionIndexer.index(3, position_3)

    assert PropertyIndex.lookup(indexer.index, {:open_files, :e}) ==
             MapSet.new([1, 2, 3])

    assert PropertyIndex.lookup(indexer.index, {:open_files, :a}) ==
             MapSet.new([2])

    assert PropertyIndex.lookup(indexer.index, {:open_files, :b}) ==
             MapSet.new([1, 3])
  end

  test "indexes multiple properties" do
    indexer =
      PositionIndexer.new([
        {:first_property, fn _position -> [:a, :b] end},
        {:second_property, fn _position -> [:x] end}
      ])

    indexer = PositionIndexer.index(indexer, 42, :position)

    assert PropertyIndex.lookup(indexer.index, {:first_property, :a}) ==
             MapSet.new([42])

    assert PropertyIndex.lookup(indexer.index, {:first_property, :b}) ==
             MapSet.new([42])

    assert PropertyIndex.lookup(indexer.index, {:second_property, :x}) ==
             MapSet.new([42])
  end

  test "indexes multiple positions independently" do
    indexer =
      PositionIndexer.new([
        {:property, fn position -> [position] end}
      ])

    indexer =
      indexer
      |> PositionIndexer.index(1, :a)
      |> PositionIndexer.index(2, :b)

    assert PropertyIndex.lookup(indexer.index, {:property, :a}) ==
             MapSet.new([1])

    assert PropertyIndex.lookup(indexer.index, {:property, :b}) ==
             MapSet.new([2])
  end

  test "returns the number of position IDs for a property" do
    index =
      PropertyIndex.new()
      |> PropertyIndex.add({:open_files, :e}, 1)
      |> PropertyIndex.add({:open_files, :e}, 2)
      |> PropertyIndex.add({:open_files, :e}, 3)

    assert PropertyIndex.cardinality(index, {:open_files, :e}) == 3
  end

  test "returns zero for an unknown property" do
    index = PropertyIndex.new()

    assert PropertyIndex.cardinality(index, {:open_files, :e}) == 0
  end

  test "indexes a scalar property value as one value" do
    property = fn _position -> %{white: 1, black: 1} end

    indexer =
      PositionIndexer.new([
        {:material, property}
      ])

    indexer = PositionIndexer.index(indexer, 1, :position)

    assert PropertyIndex.lookup(
             indexer.index,
             {:material, %{white: 1, black: 1}}
           ) == MapSet.new([1])
  end
end
