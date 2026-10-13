defmodule Analysis.PostgresPositionSemiOpenFilesTest do
  use ExUnit.Case, async: false

  alias Analysis.PositionPropertyKeyCodec
  alias Analysis.PositionQuery, as: Query
  alias Analysis.PositionStore
  alias Chess.Position
  alias Chess.PositionProperties
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

  test "indexes color-specific semi-open files for batch inserts" do
    white_e = position_with_pawns("d4", "e5")
    black_e = position_with_pawns("e4", "d5")
    empty = Position.new()

    assert {:ok, [white_id, black_id, empty_id]} =
             PositionStore.append_many([
               white_e,
               black_e,
               empty
             ])

    assert {:ok,
            %PositionStore.Page{
              entries: [^white_id],
              next: nil
            }} =
             PositionStore.page(
               Query.property(:semi_open_files, {:white, :e}),
               limit: 10
             )

    assert {:ok,
            %PositionStore.Page{
              entries: [^black_id],
              next: nil
            }} =
             PositionStore.page(
               Query.property(:semi_open_files, {:black, :e}),
               limit: 10
             )

    {:ok, white_key} =
      PositionPropertyKeyCodec.encode(
        :semi_open_files,
        {:white, :e}
      )

    assert [[properties]] =
             Repo.query!(
               """
               SELECT properties
               FROM position_features
               WHERE position_id = $1
               """,
               [white_id]
             ).rows

    assert white_key in properties

    refute empty_id in [white_id, black_id]
  end

  test "pages a pawn neighborhood combined with semi-open file and material" do
    source = position_with_pawns("d4", "e5")
    white_shift = position_with_pawns("d5", "e5")
    black_shift = position_with_pawns("d4", "d6")
    distant = position_with_pawns("a2", "e5")

    different_material =
      source
      |> Position.put_piece(
        Square.from_algebraic("b1"),
        {:white, :knight}
      )

    source_id = PositionStore.append(source)
    shift_id = PositionStore.append(white_shift)
    black_shift_id = PositionStore.append(black_shift)
    distant_id = PositionStore.append(distant)
    different_material_id = PositionStore.append(different_material)

    query =
      Query.all([
        Query.pawn_structure_edit_neighborhood(source, 2),
        Query.property(
          :semi_open_files,
          {:white, :e}
        ),
        Query.property(
          :material,
          PositionProperties.material(source)
        )
      ])

    assert {:ok,
            %PositionStore.Page{
              entries: [^source_id],
              next: cursor
            }} =
             PositionStore.page(
               query,
               limit: 1
             )

    assert %PositionStore.Cursor{} = cursor

    assert {:ok,
            %PositionStore.Page{
              entries: [^shift_id],
              next: nil
            }} =
             PositionStore.page(
               query,
               limit: 1,
               cursor: cursor
             )

    refute black_shift_id in [source_id, shift_id]
    refute distant_id in [source_id, shift_id]
    refute different_material_id in [source_id, shift_id]
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
end
