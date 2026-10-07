defmodule Analysis.GameSearchPawnStructureSinglePushSymmetryNeighborhoodTest do
  use ExUnit.Case, async: false

  alias Analysis.GameContent
  alias Analysis.GameFingerprint
  alias Analysis.GameRecord
  alias Analysis.GameRecordStore
  alias Analysis.GameSearch
  alias Analysis.GameStore
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
        game_records,
        game_occurrences,
        games,
        position_features,
        positions
      RESTART IDENTITY
      CASCADE
      """,
      []
    )

    :ok
  end

  test "finds games through exact, shifted and symmetry-expanded pawn structures" do
    source =
      position(
        "b2",
        "f7"
      )

    white_shift =
      position(
        "b3",
        "f7"
      )

    reflected_white_shift =
      position(
        "g3",
        "c7"
      )

    color_reversed_black_shift =
      position(
        "f3",
        "b7"
      )

    double_shift =
      position(
        "b3",
        "f6"
      )

    {
      source_position_id,
      source_record
    } =
      stored_game_with_record(
        "source",
        source
      )

    {
      white_shift_position_id,
      white_shift_record
    } =
      stored_game_with_record(
        "white-shift",
        white_shift
      )

    {
      reflected_white_shift_position_id,
      reflected_white_shift_record
    } =
      stored_game_with_record(
        "reflected-white-shift",
        reflected_white_shift
      )

    {
      color_reversed_black_shift_position_id,
      color_reversed_black_shift_record
    } =
      stored_game_with_record(
        "color-reversed-black-shift",
        color_reversed_black_shift
      )

    {
      double_shift_position_id,
      double_shift_record
    } =
      stored_game_with_record(
        "double-shift",
        double_shift
      )

    assert {
             :ok,
             %GameSearch.Page{
               entries: entries,
               next: nil
             }
           } =
             GameSearch.page(
               Query.pawn_structure_single_push_symmetry_neighborhood(source),
               limit: 10
             )

    assert Enum.map(
             entries,
             fn
               {
                 record,
                 occurrence
               } ->
                 {
                   record,
                   occurrence.position_id
                 }
             end
           ) ==
             [
               {
                 source_record,
                 source_position_id
               },
               {
                 white_shift_record,
                 white_shift_position_id
               },
               {
                 reflected_white_shift_record,
                 reflected_white_shift_position_id
               },
               {
                 color_reversed_black_shift_record,
                 color_reversed_black_shift_position_id
               }
             ]

    returned_records =
      Enum.map(
        entries,
        fn
          {
            record,
            _occurrence
          } ->
            record
        end
      )

    refute double_shift_record in returned_records

    returned_position_ids =
      Enum.map(
        entries,
        fn
          {
            _record,
            occurrence
          } ->
            occurrence.position_id
        end
      )

    refute double_shift_position_id in returned_position_ids
  end

  defp stored_game_with_record(record_id, position) do
    position_id =
      PositionStore.append(position)

    assert is_integer(position_id)

    assert position_id >
             0

    content =
      GameContent.new(position_id)

    {:ok, fingerprint} =
      GameFingerprint.for_content(content)

    assert {
             :ok,
             game_id
           } =
             GameStore.put(
               fingerprint,
               content,
               [
                 position_id
               ]
             )

    record =
      GameRecord.new(
        record_id,
        game_id
      )

    assert :ok =
             GameRecordStore.insert(record)

    {
      position_id,
      record
    }
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
