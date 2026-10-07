defmodule Analysis.PostgresPawnStructureSingleCaptureLikeNeighborhoodSearchTest do
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

  test "finds exact and capture-like doubled-pawn structures only" do
    source =
      position([
        {"d4", {:white, :pawn}},
        {"e4", {:white, :pawn}},
        {"c7", {:black, :pawn}}
      ])

    doubled_d_file =
      position([
        {"d4", {:white, :pawn}},
        {"d5", {:white, :pawn}},
        {"c7", {:black, :pawn}}
      ])

    doubled_e_file =
      position([
        {"e4", {:white, :pawn}},
        {"e5", {:white, :pawn}},
        {"c7", {:black, :pawn}}
      ])

    straight_shift =
      position([
        {"d4", {:white, :pawn}},
        {"e5", {:white, :pawn}},
        {"c7", {:black, :pawn}}
      ])

    missing_pawn =
      position([
        {"d4", {:white, :pawn}},
        {"c7", {:black, :pawn}}
      ])

    two_capture_like_shifts =
      position([
        {"d5", {:white, :pawn}},
        {"e5", {:white, :pawn}},
        {"c7", {:black, :pawn}}
      ])

    source_id =
      PositionStore.append(source)

    doubled_d_file_id =
      PositionStore.append(doubled_d_file)

    doubled_e_file_id =
      PositionStore.append(doubled_e_file)

    straight_shift_id =
      PositionStore.append(straight_shift)

    missing_pawn_id =
      PositionStore.append(missing_pawn)

    two_capture_like_shifts_id =
      PositionStore.append(two_capture_like_shifts)

    assert {
             :ok,
             %PositionStore.Page{
               entries: position_ids,
               next: nil
             }
           } =
             PositionStore.page(
               Query.pawn_structure_single_capture_like_neighborhood(source),
               limit: 10
             )

    assert position_ids ==
             [
               source_id,
               doubled_d_file_id,
               doubled_e_file_id
             ]

    refute straight_shift_id in position_ids
    refute missing_pawn_id in position_ids
    refute two_capture_like_shifts_id in position_ids
  end

  test "finds the same capture-like relationship from either endpoint" do
    source =
      position([
        {"d4", {:white, :pawn}},
        {"e4", {:white, :pawn}}
      ])

    doubled =
      position([
        {"d4", {:white, :pawn}},
        {"d5", {:white, :pawn}}
      ])

    source_id =
      PositionStore.append(source)

    doubled_id =
      PositionStore.append(doubled)

    assert {
             :ok,
             %PositionStore.Page{
               entries: source_query_ids,
               next: nil
             }
           } =
             PositionStore.page(
               Query.pawn_structure_single_capture_like_neighborhood(source),
               limit: 10
             )

    assert source_id in source_query_ids
    assert doubled_id in source_query_ids

    assert {
             :ok,
             %PositionStore.Page{
               entries: doubled_query_ids,
               next: nil
             }
           } =
             PositionStore.page(
               Query.pawn_structure_single_capture_like_neighborhood(doubled),
               limit: 10
             )

    assert source_id in doubled_query_ids
    assert doubled_id in doubled_query_ids
  end

  defp position(pieces) do
    Enum.reduce(
      pieces,
      Position.new(),
      fn
        {
          square,
          piece
        },
        position ->
          Position.put_piece(
            position,
            Square.from_algebraic(square),
            piece
          )
      end
    )
  end
end
