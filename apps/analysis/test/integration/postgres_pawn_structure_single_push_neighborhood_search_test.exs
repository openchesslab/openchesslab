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

  test "finds exact, forward and reverse one-pawn neighbors" do
    source =
      position(
        "h3",
        "c7"
      )

    reverse_white_shift =
      position(
        "h2",
        "c7"
      )

    forward_white_shift =
      position(
        "h4",
        "c7"
      )

    forward_black_shift =
      position(
        "h3",
        "c6"
      )

    reverse_black_shift =
      position(
        "h3",
        "c8"
      )

    double_shift =
      position(
        "h4",
        "c6"
      )

    source_id =
      PositionStore.append(source)

    reverse_white_shift_id =
      PositionStore.append(reverse_white_shift)

    forward_white_shift_id =
      PositionStore.append(forward_white_shift)

    forward_black_shift_id =
      PositionStore.append(forward_black_shift)

    reverse_black_shift_id =
      PositionStore.append(reverse_black_shift)

    double_shift_id =
      PositionStore.append(double_shift)

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
               reverse_white_shift_id,
               forward_white_shift_id,
               forward_black_shift_id,
               reverse_black_shift_id
             ]

    refute double_shift_id in position_ids
  end

  test "finds the same one-push relationship from either endpoint" do
    lower =
      position(
        "h2",
        "c7"
      )

    higher =
      position(
        "h3",
        "c7"
      )

    lower_id =
      PositionStore.append(lower)

    higher_id =
      PositionStore.append(higher)

    assert {
             :ok,
             %PositionStore.Page{
               entries: lower_query_ids,
               next: nil
             }
           } =
             PositionStore.page(
               Query.pawn_structure_single_push_neighborhood(lower),
               limit: 10
             )

    assert lower_id in lower_query_ids

    assert higher_id in lower_query_ids

    assert {
             :ok,
             %PositionStore.Page{
               entries: higher_query_ids,
               next: nil
             }
           } =
             PositionStore.page(
               Query.pawn_structure_single_push_neighborhood(higher),
               limit: 10
             )

    assert lower_id in higher_query_ids

    assert higher_id in higher_query_ids
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
