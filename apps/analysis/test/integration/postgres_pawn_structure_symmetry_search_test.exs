defmodule Analysis.PostgresPawnStructureSymmetrySearchTest do
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

  test "finds every exact pawn structure symmetry" do
    exact =
      position(
        "b4",
        "f6"
      )

    color_reversed =
      position(
        "f3",
        "b5"
      )

    file_reflected =
      position(
        "g4",
        "c6"
      )

    both =
      position(
        "c3",
        "g5"
      )

    distractor =
      position(
        "a4",
        "h6"
      )

    exact_id =
      PositionStore.append(exact)

    color_reversed_id =
      PositionStore.append(color_reversed)

    file_reflected_id =
      PositionStore.append(file_reflected)

    both_id =
      PositionStore.append(both)

    distractor_id =
      PositionStore.append(distractor)

    assert {
             :ok,
             %PositionStore.Page{
               entries: position_ids,
               next: nil
             }
           } =
             PositionStore.page(
               Query.pawn_structure_symmetries(exact),
               limit: 10
             )

    assert position_ids ==
             [
               exact_id,
               color_reversed_id,
               file_reflected_id,
               both_id
             ]

    refute distractor_id in position_ids
  end

  test "symmetry search composes with another position predicate" do
    source =
      position(
        "b4",
        "f6"
      )

    exact =
      source

    reflected =
      position(
        "g4",
        "c6"
      )

    reflected_with_rook =
      reflected
      |> Position.put_piece(
        Square.from_algebraic("a1"),
        {:white, :rook}
      )

    exact_id =
      PositionStore.append(exact)

    reflected_id =
      PositionStore.append(reflected)

    _reflected_with_rook_id =
      PositionStore.append(reflected_with_rook)

    material =
      Chess.PositionProperties.material(source)

    query =
      Query.all([
        Query.pawn_structure_symmetries(source),
        Query.property(
          :material,
          material
        )
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
               exact_id,
               reflected_id
             ]
  end

  test "pages symmetry matches without crossing the captured high-water mark" do
    exact =
      position(
        "b4",
        "f6"
      )

    color_reversed =
      position(
        "f3",
        "b5"
      )

    file_reflected =
      position(
        "g4",
        "c6"
      )

    both =
      position(
        "c3",
        "g5"
      )

    exact_id =
      PositionStore.append(exact)

    color_reversed_id =
      PositionStore.append(color_reversed)

    file_reflected_id =
      PositionStore.append(file_reflected)

    both_id =
      PositionStore.append(both)

    query =
      Query.pawn_structure_symmetries(exact)

    assert {
             :ok,
             %PositionStore.Page{
               entries: [
                 ^exact_id,
                 ^color_reversed_id
               ],
               next: cursor
             }
           } =
             PositionStore.page(
               query,
               limit: 2
             )

    late_match =
      exact
      |> Position.put_piece(
        Square.from_algebraic("a1"),
        {:white, :rook}
      )

    late_match_id =
      PositionStore.append(late_match)

    assert {
             :ok,
             %PositionStore.Page{
               entries: [
                 ^file_reflected_id,
                 ^both_id
               ],
               next: nil
             }
           } =
             PositionStore.page(
               query,
               limit: 2,
               cursor: cursor
             )

    refute late_match_id in [
             exact_id,
             color_reversed_id,
             file_reflected_id,
             both_id
           ]
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
