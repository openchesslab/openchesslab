defmodule Analysis.PostgresPawnStructureEditNeighborhoodSearchTest do
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

  test "finds structures reachable through zero, one and two elementary edits" do
    source =
      position([
        {"d4", {:white, :pawn}},
        {"h7", {:black, :pawn}}
      ])

    one_rank_edit =
      position([
        {"d5", {:white, :pawn}},
        {"h7", {:black, :pawn}}
      ])

    one_capture_like_edit =
      position([
        {"e5", {:white, :pawn}},
        {"h7", {:black, :pawn}}
      ])

    one_removal_edit =
      position([
        {"d4", {:white, :pawn}}
      ])

    two_rank_edits =
      position([
        {"d6", {:white, :pawn}},
        {"h7", {:black, :pawn}}
      ])

    capture_plus_removal =
      position([
        {"e5", {:white, :pawn}}
      ])

    three_rank_edits =
      position([
        {"d7", {:white, :pawn}},
        {"h7", {:black, :pawn}}
      ])

    source_id =
      PositionStore.append(source)

    one_rank_edit_id =
      PositionStore.append(one_rank_edit)

    one_capture_like_edit_id =
      PositionStore.append(one_capture_like_edit)

    one_removal_edit_id =
      PositionStore.append(one_removal_edit)

    two_rank_edits_id =
      PositionStore.append(two_rank_edits)

    capture_plus_removal_id =
      PositionStore.append(capture_plus_removal)

    three_rank_edits_id =
      PositionStore.append(three_rank_edits)

    assert {
             :ok,
             %PositionStore.Page{
               entries: position_ids,
               next: nil
             }
           } =
             PositionStore.page(
               Query.pawn_structure_edit_neighborhood(
                 source,
                 2
               ),
               limit: 10
             )

    assert position_ids ==
             [
               source_id,
               one_rank_edit_id,
               one_capture_like_edit_id,
               one_removal_edit_id,
               two_rank_edits_id,
               capture_plus_removal_id
             ]

    refute three_rank_edits_id in position_ids
  end

  test "does not turn directional pawn removal into pawn addition" do
    full =
      position([
        {"d4", {:white, :pawn}},
        {"h7", {:black, :pawn}}
      ])

    reduced =
      position([
        {"d4", {:white, :pawn}}
      ])

    full_id =
      PositionStore.append(full)

    reduced_id =
      PositionStore.append(reduced)

    assert {
             :ok,
             %PositionStore.Page{
               entries: position_ids,
               next: nil
             }
           } =
             PositionStore.page(
               Query.pawn_structure_edit_neighborhood(
                 reduced,
                 2
               ),
               limit: 10
             )

    assert reduced_id in position_ids

    refute full_id in position_ids
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
