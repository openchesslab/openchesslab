defmodule Analysis.PostgresPositionSideToMoveTest do
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

  test "batch inserts index opposite sides for otherwise identical positions" do
    white =
      Position.new(side_to_move: :white)
      |> place("d4", {:white, :pawn})

    black =
      Position.new(side_to_move: :black)
      |> place("d4", {:white, :pawn})

    assert {:ok, [white_id, black_id]} =
             PositionStore.append_many([white, black])

    refute white_id == black_id

    assert {:ok, %PositionStore.Page{entries: [^white_id], next: nil}} =
             PositionStore.page(
               Query.property(:side_to_move, :white),
               limit: 10
             )

    assert {:ok, %PositionStore.Page{entries: [^black_id], next: nil}} =
             PositionStore.page(
               Query.property(:side_to_move, :black),
               limit: 10
             )

    assert {:ok, black_key} =
             PositionPropertyKeyCodec.encode(:side_to_move, :black)

    assert [[properties]] =
             Repo.query!(
               "SELECT properties FROM position_features WHERE position_id = $1",
               [black_id]
             ).rows

    assert black_key in properties
  end

  test "pages a pawn neighborhood with side to move, outpost and semi-open file" do
    source = white_outpost_position()
    with_rook = place(source, "a1", {:white, :rook})
    with_bishop = place(source, "c1", {:white, :bishop})
    black_to_move = %{source | side_to_move: :black}
    no_outpost = place(source, "e5", {:white, :bishop})

    source_id = PositionStore.append(source)
    rook_id = PositionStore.append(with_rook)
    bishop_id = PositionStore.append(with_bishop)
    black_id = PositionStore.append(black_to_move)
    no_outpost_id = PositionStore.append(no_outpost)

    query =
      Query.all([
        Query.pawn_structure_edit_neighborhood(source, 1),
        Query.property(:side_to_move, :white),
        Query.property(:outposts, {:white, square("e5")}),
        Query.property(:semi_open_files, {:white, :e})
      ])

    assert {:ok,
            %PositionStore.Page{
              entries: [^source_id, ^rook_id],
              next: cursor
            }} = PositionStore.page(query, limit: 2)

    assert %PositionStore.Cursor{} = cursor

    assert {:ok, %PositionStore.Page{entries: [^bishop_id], next: nil}} =
             PositionStore.page(query, limit: 2, cursor: cursor)

    assert {:ok, %PositionStore.Page{entries: [^black_id], next: nil}} =
             PositionStore.page(
               Query.all([
                 Query.pawn_structure_edit_neighborhood(source, 1),
                 Query.property(:side_to_move, :black)
               ]),
               limit: 10
             )

    refute no_outpost_id in [source_id, rook_id, bishop_id]
  end

  defp white_outpost_position do
    Position.new(side_to_move: :white)
    |> place("e5", {:white, :knight})
    |> place("d4", {:white, :pawn})
    |> place("a7", {:black, :pawn})
    |> place("e7", {:black, :pawn})
  end

  defp place(position, algebraic, piece) do
    Position.put_piece(position, square(algebraic), piece)
  end

  defp square(algebraic), do: Square.from_algebraic(algebraic)
end
