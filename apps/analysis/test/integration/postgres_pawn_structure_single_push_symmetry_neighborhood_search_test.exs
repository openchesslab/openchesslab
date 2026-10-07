defmodule Analysis.PostgresPawnStructureSinglePushSymmetryNeighborhoodSearchTest do
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

  test "finds exact, shifted and symmetry-expanded single-push pawn structures" do
    source =
      position(
        "b2",
        "f7"
      )

    white_shift =
      position(
        "b3",
        "f7"
      )

    reflected_white_shift =
      position(
        "g3",
        "c7"
      )

    color_reversed_black_shift =
      position(
        "f3",
        "b7"
      )

    double_shift =
      position(
        "b3",
        "f6"
      )

    reflected_double_shift =
      position(
        "g3",
        "c6"
      )

    source_id =
      PositionStore.append(source)

    white_shift_id =
      PositionStore.append(white_shift)

    reflected_white_shift_id =
      PositionStore.append(reflected_white_shift)

    color_reversed_black_shift_id =
      PositionStore.append(color_reversed_black_shift)

    double_shift_id =
      PositionStore.append(double_shift)

    reflected_double_shift_id =
      PositionStore.append(reflected_double_shift)

    assert {
             :ok,
             %PositionStore.Page{
               entries: position_ids,
               next: nil
             }
           } =
             PositionStore.page(
               Query.pawn_structure_single_push_symmetry_neighborhood(source),
               limit: 20
             )

    assert source_id in position_ids
    assert white_shift_id in position_ids
    assert reflected_white_shift_id in position_ids
    assert color_reversed_black_shift_id in position_ids

    refute double_shift_id in position_ids
    refute reflected_double_shift_id in position_ids
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
