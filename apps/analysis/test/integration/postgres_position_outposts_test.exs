defmodule Analysis.PostgresPositionOutpostsTest do
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

  test "indexes both colors' knight outposts on batch insert" do
    white = white_outpost_position()

    black =
      Position.new()
      |> place("d4", {:black, :knight})
      |> place("e5", {:black, :pawn})
      |> place("a2", {:white, :pawn})

    blocked =
      white
      |> place("f6", {:black, :pawn})

    assert {:ok, [white_id, black_id, blocked_id]} =
             PositionStore.append_many([white, black, blocked])

    assert {:ok, %PositionStore.Page{entries: [^white_id], next: nil}} =
             PositionStore.page(
               Query.property(:outposts, {:white, square("e5")}),
               limit: 10
             )

    assert {:ok, %PositionStore.Page{entries: [^black_id], next: nil}} =
             PositionStore.page(
               Query.property(:outposts, {:black, square("d4")}),
               limit: 10
             )

    assert {:ok, key} =
             PositionPropertyKeyCodec.encode(
               :outposts,
               {:white, square("e5")}
             )

    assert [[properties]] =
             Repo.query!(
               "SELECT properties FROM position_features WHERE position_id = $1",
               [white_id]
             ).rows

    assert key in properties
    refute blocked_id in [white_id, black_id]
  end

  test "pages outposts combined with pawn neighborhood and semi-open file" do
    source =
      white_outpost_position()
      |> place("e7", {:black, :pawn})

    with_rook = place(source, "a1", {:white, :rook})
    with_bishop = place(source, "c1", {:white, :bishop})

    # Removing the black e-pawn preserves the outpost but closes
    # the white semi-open-file condition (the e-file becomes open).
    no_semi_open = white_outpost_position()

    # Keeping the pawns but replacing the knight removes the outpost.
    no_outpost = place(source, "e5", {:white, :bishop})

    source_id = PositionStore.append(source)
    rook_id = PositionStore.append(with_rook)
    bishop_id = PositionStore.append(with_bishop)
    no_semi_open_id = PositionStore.append(no_semi_open)
    no_outpost_id = PositionStore.append(no_outpost)

    query =
      Query.all([
        Query.pawn_structure_edit_neighborhood(source, 1),
        Query.property(:outposts, {:white, square("e5")}),
        Query.property(:semi_open_files, {:white, :e})
      ])

    assert {:ok, %PositionStore.Page{entries: [^source_id], next: cursor1}} =
             PositionStore.page(query, limit: 1)

    assert %PositionStore.Cursor{} = cursor1

    assert {:ok, %PositionStore.Page{entries: [^rook_id], next: cursor2}} =
             PositionStore.page(query, limit: 1, cursor: cursor1)

    assert %PositionStore.Cursor{} = cursor2

    assert {:ok, %PositionStore.Page{entries: [^bishop_id], next: nil}} =
             PositionStore.page(query, limit: 1, cursor: cursor2)

    refute no_semi_open_id in [source_id, rook_id, bishop_id]
    refute no_outpost_id in [source_id, rook_id, bishop_id]
  end

  defp white_outpost_position do
    Position.new()
    |> place("e5", {:white, :knight})
    |> place("d4", {:white, :pawn})
    |> place("a7", {:black, :pawn})
  end

  defp place(position, algebraic, piece) do
    Position.put_piece(position, square(algebraic), piece)
  end

  defp square(algebraic), do: Square.from_algebraic(algebraic)
end
