defmodule Analysis.PostgresPositionInCheckTest do
  use ExUnit.Case, async: false

  alias Analysis.PositionPropertyKeyCodec
  alias Analysis.PositionQuery, as: Query
  alias Analysis.PositionStore
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

  test "indexes only the kings that are in check, including hypothetical double checks" do
    white_checked =
      Position.new(side_to_move: :white)
      |> place("e1", {:white, :king})
      |> place("h8", {:black, :king})
      |> place("e4", {:black, :rook})

    black_checked =
      Position.new(side_to_move: :black)
      |> place("a1", {:white, :king})
      |> place("e8", {:black, :king})
      |> place("e5", {:white, :rook})

    both_checked =
      Position.new(side_to_move: :white)
      |> place("e1", {:white, :king})
      |> place("e8", {:black, :king})
      |> place("e4", {:black, :rook})
      |> place("e5", {:white, :rook})

    neither_checked =
      Position.new(side_to_move: :black)
      |> place("a1", {:white, :king})
      |> place("h8", {:black, :king})

    assert {:ok, [white_id, black_id, both_id, safe_id]} =
             PositionStore.append_many([
               white_checked,
               black_checked,
               both_checked,
               neither_checked
             ])

    assert {:ok, %PositionStore.Page{entries: [^white_id, ^both_id], next: nil}} =
             PositionStore.page(Query.property(:in_check, :white), limit: 10)

    assert {:ok, %PositionStore.Page{entries: [^both_id, ^black_id], next: nil}} =
             PositionStore.page(Query.property(:in_check, :black), limit: 10)

    {:ok, white_key} = PositionPropertyKeyCodec.encode(:in_check, :white)
    {:ok, black_key} = PositionPropertyKeyCodec.encode(:in_check, :black)

    assert [[both_properties]] =
             Repo.query!(
               "SELECT properties FROM position_features WHERE position_id = $1",
               [both_id]
             ).rows

    assert white_key in both_properties
    assert black_key in both_properties

    assert [[safe_properties]] =
             Repo.query!(
               "SELECT properties FROM position_features WHERE position_id = $1",
               [safe_id]
             ).rows

    refute white_key in safe_properties
    refute black_key in safe_properties
  end

  test "pages checked positions with side to move and supports negation" do
    first =
      Position.new(side_to_move: :white)
      |> place("e1", {:white, :king})
      |> place("h8", {:black, :king})
      |> place("e4", {:black, :rook})

    second = place(first, "a2", {:white, :pawn})
    black_turn = %{first | side_to_move: :black}
    safe = Position.new(side_to_move: :white)

    first_id = PositionStore.append(first)
    second_id = PositionStore.append(second)
    black_id = PositionStore.append(black_turn)
    safe_id = PositionStore.append(safe)

    query =
      Query.all([
        Query.property(:in_check, :white),
        Query.property(:side_to_move, :white)
      ])

    assert {:ok, %PositionStore.Page{entries: [^first_id], next: cursor}} =
             PositionStore.page(query, limit: 1)

    assert %PositionStore.Cursor{} = cursor

    assert {:ok, %PositionStore.Page{entries: [^second_id], next: nil}} =
             PositionStore.page(query, limit: 1, cursor: cursor)

    assert {:ok, %PositionStore.Page{entries: [^safe_id], next: nil}} =
             PositionStore.page(
               Query.all([
                 Query.negate(Query.property(:in_check, :white)),
                 Query.property(:side_to_move, :white)
               ]),
               limit: 10
             )

    refute black_id in [first_id, second_id]
  end

  defp place(position, algebraic, piece) do
    Position.put_piece(position, Square.from_algebraic(algebraic), piece)
  end
end
