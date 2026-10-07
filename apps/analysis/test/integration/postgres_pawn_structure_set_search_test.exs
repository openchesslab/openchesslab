defmodule Analysis.PostgresPawnStructureSetSearchTest do
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

  test "searches a bounded set of exact pawn structures in one page query" do
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

    other =
      position(
        "h4",
        "c7"
      )

    source_id =
      PositionStore.append(source)

    shifted_id =
      PositionStore.append(shifted)

    other_id =
      PositionStore.append(other)

    query =
      Query.pawn_structures([
        PawnStructure.from_position(source),
        PawnStructure.from_position(shifted)
      ])

    assert {
             :ok,
             %PositionStore.Page{
               entries: position_ids,
               next: nil
             }
           } =
             PositionStore.page(
               query,
               limit: 10
             )

    assert position_ids ==
             [
               source_id,
               shifted_id
             ]

    refute other_id in position_ids
  end

  defp position(white_square, black_square) do
    Position.new()
    |> Position.put_piece(
      Square.from_algebraic(white_square),
      {:white, :pawn}
    )
    |> Position.put_piece(
      Square.from_algebraic(black_square),
      {:black, :pawn}
    )
  end
end
