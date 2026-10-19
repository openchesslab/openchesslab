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

    other_id =
      PositionStore.append(same_reversed_pawns_different_material)

    digest_positions([matching_id, other_id])

    query =
      Query.all([
        Query.color_reversed_pawn_structure(source),
        Query.digests([material_signature(matching)])
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

  # The material digest of a position: its material signature atom. Digests
  # of the appended positions power the non-structural predicate.
  defp material_signature(position) do
    {:ok, result} = Analysis.PositionFeatures.extract(position)

    result.features
    |> Analysis.FeatureDigest.atoms()
    |> Enum.find(&String.starts_with?(&1, "material.signature:w:"))
  end

  defp digest_positions(ids) do
    Enum.each(ids, fn id ->
      {:ok, _ids} = Analysis.PositionDigests.store_position_id(id)
    end)
  end
end
