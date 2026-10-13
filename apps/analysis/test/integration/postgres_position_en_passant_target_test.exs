defmodule Analysis.PostgresPositionEnPassantTargetTest do
  use ExUnit.Case, async: false

  alias Analysis.PositionPropertyKeyCodec
  alias Analysis.PositionQuery, as: Query
  alias Analysis.PositionStore
  alias Chess.Move
  alias Chess.Position
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

  test "batch inserts index en passant targets from actual double pawn moves" do
    white_double = after_white_double_push()
    black_double = after_black_double_push()
    without_target = %{white_double | en_passant: nil}

    assert white_double.en_passant == square("e3")
    assert black_double.en_passant == square("e6")

    assert {:ok, [white_id, black_id, none_id]} =
             PositionStore.append_many([white_double, black_double, without_target])

    assert {:ok, %PositionStore.Page{entries: [^white_id], next: nil}} =
             PositionStore.page(
               Query.property(:en_passant_target, square("e3")),
               limit: 10
             )

    assert {:ok, %PositionStore.Page{entries: [^black_id], next: nil}} =
             PositionStore.page(
               Query.property(:en_passant_target, square("e6")),
               limit: 10
             )

    {:ok, white_key} =
      PositionPropertyKeyCodec.encode(:en_passant_target, square("e3"))

    {:ok, black_key} =
      PositionPropertyKeyCodec.encode(:en_passant_target, square("e6"))

    assert [[properties]] =
             Repo.query!(
               "SELECT properties FROM position_features WHERE position_id = $1",
               [white_id]
             ).rows

    assert white_key in properties
    refute black_key in properties

    assert [[none_properties]] =
             Repo.query!(
               "SELECT properties FROM position_features WHERE position_id = $1",
               [none_id]
             ).rows

    refute white_key in none_properties
    refute black_key in none_properties
  end

  test "en passant target disappears after the next pawn move" do
    with_target = after_white_double_push()

    assert {:ok, after_response} =
             Position.apply_move(with_target, move("d4", "d3"))

    assert after_response.en_passant == nil

    target_id = PositionStore.append(with_target)
    response_id = PositionStore.append(after_response)

    assert {:ok, %PositionStore.Page{entries: [^target_id], next: nil}} =
             PositionStore.page(
               Query.property(:en_passant_target, square("e3")),
               limit: 10
             )

    assert {:ok, %PositionStore.Page{entries: [^response_id], next: nil}} =
             PositionStore.page(
               Query.negate(Query.property(:en_passant_target, square("e3"))),
               limit: 10
             )
  end

  test "pages target-square searches combined with side to move" do
    first = after_white_double_push()
    second = place(first, "a1", {:white, :rook})
    third = place(first, "c1", {:white, :bishop})
    none = %{first | en_passant: nil}
    other_side = %{first | side_to_move: :white}

    first_id = PositionStore.append(first)
    second_id = PositionStore.append(second)
    third_id = PositionStore.append(third)
    none_id = PositionStore.append(none)
    other_side_id = PositionStore.append(other_side)

    query =
      Query.all([
        Query.property(:en_passant_target, square("e3")),
        Query.property(:side_to_move, :black)
      ])

    assert {:ok, %PositionStore.Page{entries: [^first_id], next: cursor1}} =
             PositionStore.page(query, limit: 1)

    assert %PositionStore.Cursor{} = cursor1

    assert {:ok, %PositionStore.Page{entries: [^second_id], next: cursor2}} =
             PositionStore.page(query, limit: 1, cursor: cursor1)

    assert %PositionStore.Cursor{} = cursor2

    assert {:ok, %PositionStore.Page{entries: [^third_id], next: nil}} =
             PositionStore.page(query, limit: 1, cursor: cursor2)

    refute none_id in [first_id, second_id, third_id]
    refute other_side_id in [first_id, second_id, third_id]
  end

  defp after_white_double_push do
    position =
      Position.new(side_to_move: :white)
      |> place("e2", {:white, :pawn})
      |> place("d4", {:black, :pawn})

    {:ok, after_move} = Position.apply_move(position, move("e2", "e4"))
    after_move
  end

  defp after_black_double_push do
    position =
      Position.new(side_to_move: :black)
      |> place("e7", {:black, :pawn})
      |> place("d5", {:white, :pawn})

    {:ok, after_move} = Position.apply_move(position, move("e7", "e5"))
    after_move
  end

  defp place(position, algebraic, piece) do
    Position.put_piece(position, square(algebraic), piece)
  end

  defp move(from, to), do: Move.new(square(from), square(to))

  defp square(algebraic), do: Square.from_algebraic(algebraic)
end
