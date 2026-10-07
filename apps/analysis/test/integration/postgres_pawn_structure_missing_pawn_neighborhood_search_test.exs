defmodule Analysis.PostgresPawnStructureMissingPawnNeighborhoodSearchTest do
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

  test "finds exact and one-missing-pawn structures only" do
    source =
      position([
        {"h2", {:white, :pawn}},
        {"d4", {:white, :pawn}},
        {"c7", {:black, :pawn}}
      ])

    missing_h_pawn =
      position([
        {"d4", {:white, :pawn}},
        {"c7", {:black, :pawn}}
      ])

    missing_d_pawn =
      position([
        {"h2", {:white, :pawn}},
        {"c7", {:black, :pawn}}
      ])

    missing_black_pawn =
      position([
        {"h2", {:white, :pawn}},
        {"d4", {:white, :pawn}}
      ])

    missing_two_pawns =
      position([
        {"d4", {:white, :pawn}}
      ])

    shifted_pawn =
      position([
        {"h3", {:white, :pawn}},
        {"d4", {:white, :pawn}},
        {"c7", {:black, :pawn}}
      ])

    source_id =
      PositionStore.append(source)

    missing_h_pawn_id =
      PositionStore.append(missing_h_pawn)

    missing_d_pawn_id =
      PositionStore.append(missing_d_pawn)

    missing_black_pawn_id =
      PositionStore.append(missing_black_pawn)

    missing_two_pawns_id =
      PositionStore.append(missing_two_pawns)

    shifted_pawn_id =
      PositionStore.append(shifted_pawn)

    assert {
             :ok,
             %PositionStore.Page{
               entries: position_ids,
               next: nil
             }
           } =
             PositionStore.page(
               Query.pawn_structure_missing_pawn_neighborhood(source),
               limit: 10
             )

    assert position_ids ==
             [
               source_id,
               missing_h_pawn_id,
               missing_d_pawn_id,
               missing_black_pawn_id
             ]

    refute missing_two_pawns_id in position_ids
    refute shifted_pawn_id in position_ids
  end

  test "does not implicitly add a pawn when queried from the reduced structure" do
    full =
      position([
        {"h2", {:white, :pawn}},
        {"c7", {:black, :pawn}}
      ])

    reduced =
      position([
        {"c7", {:black, :pawn}}
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
               Query.pawn_structure_missing_pawn_neighborhood(reduced),
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
