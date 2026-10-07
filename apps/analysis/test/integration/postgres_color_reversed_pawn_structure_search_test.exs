defmodule Analysis.PostgresColorReversedPawnStructureSearchTest do
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

  test "finds the exact pawn structure from the opposite color perspective" do
    source =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("d4"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("c6"),
        {:black, :pawn}
      )

    reversed =
      Position.new(side_to_move: :black)
      |> Position.put_piece(
        Square.from_algebraic("c3"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("d5"),
        {:black, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("a1"),
        {:white, :queen}
      )

    distractor =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("d4"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("c5"),
        {:black, :pawn}
      )

    source_id =
      PositionStore.append(source)

    reversed_id =
      PositionStore.append(reversed)

    distractor_id =
      PositionStore.append(distractor)

    assert {
             :ok,
             %PositionStore.Page{
               entries: [
                 ^reversed_id
               ],
               next: nil
             }
           } =
             PositionStore.page(
               Query.color_reversed_pawn_structure(source),
               limit: 10
             )

    refute source_id ==
             reversed_id

    refute distractor_id ==
             reversed_id
  end

  test "color-reversed pawn structure composes with other predicates" do
    source =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("d4"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("c6"),
        {:black, :pawn}
      )

    matching =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("c3"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("d5"),
        {:black, :pawn}
      )

    same_reversed_pawns_different_material =
      matching
      |> Position.put_piece(
        Square.from_algebraic("a1"),
        {:white, :rook}
      )

    matching_id =
      PositionStore.append(matching)

    _other_id =
      PositionStore.append(same_reversed_pawns_different_material)

    material =
      Chess.PositionProperties.material(matching)

    query =
      Query.all([
        Query.color_reversed_pawn_structure(source),
        Query.property(
          :material,
          material
        )
      ])

    assert {
             :ok,
             %PositionStore.Page{
               entries: [
                 ^matching_id
               ],
               next: nil
             }
           } =
             PositionStore.page(
               query,
               limit: 10
             )
  end
end
