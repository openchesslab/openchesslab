defmodule Analysis.PostgresPawnStructureSearchTest do
  use ExUnit.Case, async: false

  alias Analysis.PositionPawnStructureCodec
  alias Analysis.PositionQuery, as: Query
  alias Analysis.PositionStore
  alias Chess.PawnStructure
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

  test "indexes pawn structure in keyset paging order" do
    assert [
             [
               index_definition
             ]
           ] =
             Repo.query!(
               """
               SELECT pg_get_indexdef(index_relation.oid)
               FROM pg_class AS index_relation
               JOIN pg_index AS index_metadata
                 ON index_metadata.indexrelid = index_relation.oid
               JOIN pg_class AS table_relation
                 ON table_relation.oid = index_metadata.indrelid
               WHERE
                 table_relation.relname = 'positions'
                 AND index_relation.relname = 'positions_pawn_structure_index'
               """,
               []
             ).rows

    normalized_definition =
      index_definition
      |> String.replace(
        ~r/\s+/,
        " "
      )
      |> String.trim()

    assert String.contains?(
             normalized_definition,
             "(white_pawns, black_pawns, id)"
           )
  end

  test "stores exact pawn occupancy in PostgreSQL" do
    position =
      Position.starting_position()

    position_id =
      PositionStore.append(position)

    structure =
      PawnStructure.from_position(position)

    assert {:ok,
            {
              white_pawns,
              black_pawns
            }} =
             PositionPawnStructureCodec.encode(structure)

    assert [
             [
               ^white_pawns,
               ^black_pawns
             ]
           ] =
             Repo.query!(
               """
               SELECT
                 white_pawns,
                 black_pawns
               FROM positions
               WHERE id = $1
               """,
               [
                 position_id
               ]
             ).rows
  end

  test "finds positions with the same pawns regardless of other position state" do
    first =
      base_structure_position()

    second =
      Position.new(side_to_move: :black)
      |> Position.put_piece(
        Square.from_algebraic("d4"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("e5"),
        {:black, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("a1"),
        {:white, :queen}
      )
      |> Position.put_piece(
        Square.from_algebraic("h8"),
        {:black, :rook}
      )

    different =
      Position.new()
      |> Position.put_piece(
        Square.from_algebraic("d5"),
        {:white, :pawn}
      )
      |> Position.put_piece(
        Square.from_algebraic("e5"),
        {:black, :pawn}
      )

    first_id =
      PositionStore.append(first)

    second_id =
      PositionStore.append(second)

    different_id =
      PositionStore.append(different)

    assert {
             :ok,
             %PositionStore.Page{
               entries: position_ids,
               next: nil
             }
           } =
             PositionStore.page(
               Query.pawn_structure(first),
               limit: 10
             )

    assert position_ids ==
             [
               first_id,
               second_id
             ]

    refute different_id in position_ids
  end

  test "searches using an explicit pawn structure" do
    position =
      base_structure_position()

    position_id =
      PositionStore.append(position)

    structure =
      PawnStructure.from_position(position)

    assert {
             :ok,
             %PositionStore.Page{
               entries: [
                 ^position_id
               ],
               next: nil
             }
           } =
             PositionStore.page(
               Query.pawn_structure(structure),
               limit: 10
             )
  end

  test "pawn structure query composes with existing predicates" do
    matching =
      base_structure_position()

    same_pawns_different_material =
      base_structure_position()
      |> Position.put_piece(
        Square.from_algebraic("a1"),
        {:white, :rook}
      )

    matching_id =
      PositionStore.append(matching)

    other_id =
      PositionStore.append(same_pawns_different_material)

    digest_positions([matching_id, other_id])

    query =
      Query.all([
        Query.pawn_structure(matching),
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

  defp base_structure_position do
    Position.new()
    |> Position.put_piece(
      Square.from_algebraic("d4"),
      {:white, :pawn}
    )
    |> Position.put_piece(
      Square.from_algebraic("e5"),
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
