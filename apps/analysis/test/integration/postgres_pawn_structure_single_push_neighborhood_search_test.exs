defmodule Analysis.PostgresPawnStructureSinglePushNeighborhoodSearchTest do
  use ExUnit.Case, async: false

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

  test "finds the exact structure and every one-pawn single-push neighbor" do
    source =
      position(
        "h2",
        "c7"
      )

    white_shift =
      position(
        "h3",
        "c7"
      )

    black_shift =
      position(
        "h2",
        "c6"
      )

    double_shift =
      position(
        "h3",
        "c6"
      )

    farther_shift =
      position(
        "h4",
        "c7"
      )

    source_id =
      PositionStore.append(source)

    white_shift_id =
      PositionStore.append(white_shift)

    black_shift_id =
      PositionStore.append(black_shift)

    double_shift_id =
      PositionStore.append(double_shift)

    farther_shift_id =
      PositionStore.append(farther_shift)

    assert {
             :ok,
             %PositionStore.Page{
               entries: position_ids,
               next: nil
             }
           } =
             PositionStore.page(
               Query.pawn_structure_single_push_neighborhood(source),
               limit: 10
             )

    assert position_ids ==
             [
               source_id,
               white_shift_id,
               black_shift_id
             ]

    refute double_shift_id in position_ids

    refute farther_shift_id in position_ids
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
