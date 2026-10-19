defmodule Analysis.PostgresPositionCompoundQueryTest do
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

  test "pages an edit neighborhood combined with a material filter" do
    source = position_with_pawns("d4", "e5")
    white_shift = position_with_pawns("d5", "e5")
    black_shift = position_with_pawns("d4", "e6")
    distant = position_with_pawns("a2", "h7")

    different_material =
      source
      |> Position.put_piece(
        Square.from_algebraic("b1"),
        {:white, :knight}
      )

    source_id = PositionStore.append(source)
    white_shift_id = PositionStore.append(white_shift)
    black_shift_id = PositionStore.append(black_shift)

    distant_id = PositionStore.append(distant)
    different_material_id = PositionStore.append(different_material)

    digest_positions([
      source_id,
      white_shift_id,
      black_shift_id,
      distant_id,
      different_material_id
    ])

    query =
      Query.all([
        Query.digests([material_signature(source)]),
        Query.pawn_structure_edit_neighborhood(source, 2)
      ])

    assert {:ok,
            %PositionStore.Page{
              entries: [^source_id],
              next: first_cursor
            }} = PositionStore.page(query, limit: 1)

    assert %PositionStore.Cursor{} = first_cursor

    assert {:ok,
            %PositionStore.Page{
              entries: [^white_shift_id],
              next: second_cursor
            }} =
             PositionStore.page(
               query,
               limit: 1,
               cursor: first_cursor
             )

    assert %PositionStore.Cursor{} = second_cursor

    assert {:ok,
            %PositionStore.Page{
              entries: [^black_shift_id],
              next: nil
            }} =
             PositionStore.page(
               query,
               limit: 1,
               cursor: second_cursor
             )

    refute distant_id in [
             source_id,
             white_shift_id,
             black_shift_id
           ]

    refute different_material_id in [
             source_id,
             white_shift_id,
             black_shift_id
           ]
  end

  test "evaluates an edit neighborhood inside a generic OR query" do
    source = position_with_pawns("d4", "e5")
    shift = position_with_pawns("d5", "e5")
    distant = position_with_pawns("a2", "h7")

    same_structure_different_material =
      source
      |> Position.put_piece(
        Square.from_algebraic("b1"),
        {:white, :knight}
      )

    distant_different_material =
      distant
      |> Position.put_piece(
        Square.from_algebraic("b1"),
        {:white, :knight}
      )

    source_id = PositionStore.append(source)
    shift_id = PositionStore.append(shift)
    distant_id = PositionStore.append(distant)

    different_material_id =
      PositionStore.append(same_structure_different_material)

    excluded_id =
      PositionStore.append(distant_different_material)

    digest_positions([source_id, shift_id, distant_id, different_material_id, excluded_id])

    query =
      Query.any([
        Query.pawn_structure_edit_neighborhood(source, 1),
        Query.digests([material_signature(source)])
      ])

    assert {:ok,
            %PositionStore.Page{
              entries: position_ids,
              next: nil
            }} =
             PositionStore.page(
               query,
               limit: 10
             )

    assert position_ids == [
             source_id,
             shift_id,
             distant_id,
             different_material_id
           ]

    refute excluded_id in position_ids
  end

  defp position_with_pawns(white_square, black_square) do
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
