defmodule Analysis.PostgresShiftedPawnStructureSearchTest do
  use ExUnit.Case, async: false

  alias Analysis.PositionQuery, as: Query
  alias Analysis.PositionStore
  alias Chess.PawnStructure
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

  test "finds the exact pawn structure after a requested pawn shift" do
    source =
      position(
        "h2",
        "c7"
      )

    shifted =
      position(
        "h3",
        "c7"
      )

    shifted_with_rook =
      shifted
      |> Position.put_piece(
        square("a1"),
        {:white, :rook}
      )

    source_id =
      PositionStore.append(source)

    shifted_id =
      PositionStore.append(shifted)

    shifted_with_rook_id =
      PositionStore.append(shifted_with_rook)

    source_structure =
      PawnStructure.from_position(source)

    assert {
             :ok,
             shifted_structure
           } =
             PawnStructure.shift_pawn(
               source_structure,
               :white,
               square("h2"),
               square("h3")
             )

    assert {
             :ok,
             %PositionStore.Page{
               entries: position_ids,
               next: nil
             }
           } =
             PositionStore.page(
               Query.pawn_structure(shifted_structure),
               limit: 10
             )

    assert position_ids ==
             [
               shifted_id,
               shifted_with_rook_id
             ]

    refute source_id in position_ids
  end

  test "shifted structures compose with symmetry search" do
    source =
      position(
        "b2",
        "f7"
      )

    shifted =
      position(
        "b3",
        "f7"
      )

    reflected =
      position(
        "g3",
        "c7"
      )

    shifted_id =
      PositionStore.append(shifted)

    reflected_id =
      PositionStore.append(reflected)

    source_structure =
      PawnStructure.from_position(source)

    assert {
             :ok,
             shifted_structure
           } =
             PawnStructure.shift_pawn(
               source_structure,
               :white,
               square("b2"),
               square("b3")
             )

    assert {
             :ok,
             %PositionStore.Page{
               entries: position_ids,
               next: nil
             }
           } =
             PositionStore.page(
               Query.pawn_structure_symmetries(shifted_structure),
               limit: 10
             )

    assert shifted_id in position_ids

    assert reflected_id in position_ids
  end

  defp position(white_square, black_square) do
    Position.new()
    |> Position.put_piece(
      square(white_square),
      {:white, :pawn}
    )
    |> Position.put_piece(
      square(black_square),
      {:black, :pawn}
    )
  end

  defp square(algebraic) do
    Square.from_algebraic(algebraic)
  end
end
