defmodule Analysis.PostgresFileReflectedPawnStructureSearchTest do
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

  test "finds the exact pawn structure reflected across files" do
    source =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("b4"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("f6"),
        {:black, :pawn}
      )

    reflected =
      Position.new(side_to_move: :black)
      |> Position.put_piece(
        Square.from_algebraic("g4"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("c6"),
        {:black, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("a1"),
        {:white, :queen}
      )

    distractor =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("g4"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("d6"),
        {:black, :pawn}
      )

    source_id =
      PositionStore.append(source)

    reflected_id =
      PositionStore.append(reflected)

    distractor_id =
      PositionStore.append(distractor)

    assert {
             :ok,
             %PositionStore.Page{
               entries: [
                 ^reflected_id
               ],
               next: nil
             }
           } =
             PositionStore.page(
               Query.file_reflected_pawn_structure(source),
               limit: 10
             )

    refute source_id ==
             reflected_id

    refute distractor_id ==
             reflected_id
  end

  test "file-reflected pawn structure composes with other predicates" do
    source =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("b4"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("f6"),
        {:black, :pawn}
      )

    matching =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("g4"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("c6"),
        {:black, :pawn}
      )

    same_reflected_pawns_different_material =
      matching
      |> Position.put_piece(
        Square.from_algebraic("a1"),
        {:white, :rook}
      )

    matching_id =
      PositionStore.append(matching)

    _other_id =
      PositionStore.append(same_reflected_pawns_different_material)

    material =
      Chess.PositionProperties.material(matching)

    query =
      Query.all([
        Query.file_reflected_pawn_structure(source),
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
