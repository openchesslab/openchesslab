defmodule Analysis.PostgresPositionCastlingRightsTest do
  use ExUnit.Case, async: false

  alias Analysis.PositionPropertyKeyCodec
  alias Analysis.PositionQuery, as: Query
  alias Analysis.PositionStore
  alias Chess.Position
  alias Chess.PositionProperties
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

  test "batch inserts preserve each individual castling right" do
    all_rights = Position.starting_position()

    white_rights =
      with_rights(all_rights, [:white_kingside, :white_queenside])

    black_rights =
      with_rights(all_rights, [:black_kingside, :black_queenside])

    no_rights = with_rights(all_rights, [])

    assert {:ok, [all_id, white_id, black_id, none_id]} =
             PositionStore.append_many([
               all_rights,
               white_rights,
               black_rights,
               no_rights
             ])

    assert {:ok, %PositionStore.Page{entries: white_ids, next: nil}} =
             PositionStore.page(
               Query.property(:castling_right, :white_kingside),
               limit: 10
             )

    assert white_ids == Enum.sort([all_id, white_id])

    assert {:ok, %PositionStore.Page{entries: black_ids, next: nil}} =
             PositionStore.page(
               Query.property(:castling_right, :black_queenside),
               limit: 10
             )

    assert black_ids == Enum.sort([all_id, black_id])

    assert {:ok, key} =
             PositionPropertyKeyCodec.encode(
               :castling_right,
               :white_kingside
             )

    assert [[all_properties]] =
             Repo.query!(
               "SELECT properties FROM position_features WHERE position_id = $1",
               [all_id]
             ).rows

    assert [[none_properties]] =
             Repo.query!(
               "SELECT properties FROM position_features WHERE position_id = $1",
               [none_id]
             ).rows

    assert key in all_properties
    refute key in none_properties
  end

  test "pages castling rights combined with side to move and material" do
    original = Position.starting_position()
    white_kingside = with_rights(original, [:white_kingside])
    white_both = with_rights(original, [:white_kingside, :white_queenside])
    white_and_black = with_rights(original, [:white_kingside, :black_kingside])
    black_turn = %{original | side_to_move: :black}
    no_kingside = with_rights(original, [:white_queenside])
    no_rights = with_rights(original, [])

    first_id = PositionStore.append(white_kingside)
    second_id = PositionStore.append(white_both)
    third_id = PositionStore.append(white_and_black)
    black_turn_id = PositionStore.append(black_turn)
    no_kingside_id = PositionStore.append(no_kingside)
    no_rights_id = PositionStore.append(no_rights)

    query =
      Query.all([
        Query.property(:castling_right, :white_kingside),
        Query.property(:side_to_move, :white),
        Query.property(:material, PositionProperties.material(original))
      ])

    assert {:ok, %PositionStore.Page{entries: [^first_id], next: cursor1}} =
             PositionStore.page(query, limit: 1)

    assert %PositionStore.Cursor{} = cursor1

    assert {:ok, %PositionStore.Page{entries: [^second_id], next: cursor2}} =
             PositionStore.page(query, limit: 1, cursor: cursor1)

    assert %PositionStore.Cursor{} = cursor2

    assert {:ok, %PositionStore.Page{entries: [^third_id], next: nil}} =
             PositionStore.page(query, limit: 1, cursor: cursor2)

    assert {:ok, %PositionStore.Page{entries: absent_ids, next: nil}} =
             PositionStore.page(
               Query.all([
                 Query.property(:side_to_move, :white),
                 Query.negate(Query.property(:castling_right, :white_kingside))
               ]),
               limit: 10
             )

    assert absent_ids == [no_kingside_id, no_rights_id]
    refute black_turn_id in [first_id, second_id, third_id]
  end

  defp with_rights(position, rights) do
    %{position | castling_rights: MapSet.new(rights)}
  end
end
