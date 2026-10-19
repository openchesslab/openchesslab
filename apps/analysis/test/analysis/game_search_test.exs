defmodule Analysis.GameSearchTest do
  use ExUnit.Case, async: false

  alias Analysis.GameContent
  alias Analysis.GameFingerprint
  alias Analysis.GameOccurrence
  alias Analysis.GameRecord
  alias Analysis.GameRecordQuery
  alias Analysis.GameRecords
  alias Analysis.GameRecordStore
  alias Analysis.GameSearch
  alias Analysis.GameStart
  alias Analysis.GameStore
  alias Analysis.PositionQuery, as: Query
  alias Analysis.PositionStore
  alias Chess.Move
  alias Chess.Position
  alias Chess.Square
  alias OpenChessLab.Repo

  setup do
    Repo.query!(
      """
      TRUNCATE TABLE
        game_records,
        game_occurrences,
        games,
        positions
      RESTART IDENTITY
      CASCADE
      """,
      []
    )

    :ok
  end

  test "executes position and record predicates in one PostgreSQL query" do
    first_position =
      Position.starting_position()

    {:ok, second_position} =
      Position.apply_move(
        first_position,
        move(
          "e2",
          "e4"
        )
      )

    {
      first_position_id,
      first_game_id
    } =
      stored_game(first_position)

    {
      _second_position_id,
      second_game_id
    } =
      stored_game(second_position)

    matching_record =
      GameRecord.new(
        "record-1",
        first_game_id,
        %{
          "white" => "Magnus Carlsen",
          "event" => "Wijk aan Zee"
        }
      )

    excluded_by_record_query =
      GameRecord.new(
        "record-2",
        first_game_id,
        %{
          "white" => "Other Player",
          "event" => "Wijk aan Zee"
        }
      )

    excluded_by_position_query =
      GameRecord.new(
        "record-3",
        second_game_id,
        %{
          "white" => "Magnus Carlsen",
          "event" => "London"
        }
      )

    for record <- [
          matching_record,
          excluded_by_record_query,
          excluded_by_position_query
        ] do
      assert :ok =
               GameRecordStore.insert(record)
    end

    record_query =
      GameRecordQuery.metadata_contains(%{
        "white" => "Magnus Carlsen"
      })

    {
      result,
      query_count
    } =
      query_count(fn ->
        GameSearch.page(
          Query.equivalent(first_position),
          record_query,
          limit: 10
        )
      end)

    assert query_count ==
             1

    assert {
             :ok,
             %GameSearch.Page{
               entries: [
                 {
                   ^matching_record,
                   occurrence
                 }
               ],
               next: nil
             }
           } =
             result

    assert occurrence.game_id ==
             first_game_id

    assert occurrence.ply ==
             0

    assert occurrence.position_id ==
             first_position_id
  end

  test "combines player substring, result and exact position in one search" do
    start_id = PositionStore.append(Position.starting_position())

    {:ok, after_e4} =
      Position.apply_move(Position.starting_position(), move("e2", "e4"))

    # Carlsen wins with 1.e4 e5; the same player loses with 1.d4 d5; a third
    # game with 1.e4 belongs to someone else.
    {:ok, carlsen_win} =
      GameRecords.create(
        "record-carlsen-win",
        GameContent.new(start_id, [move("e2", "e4"), move("e7", "e5")]),
        GameStart.standard(),
        %{"white" => "Magnus Carlsen", "black" => "Opponent", "result" => "1-0"}
      )

    {:ok, _carlsen_loss} =
      GameRecords.create(
        "record-carlsen-loss",
        GameContent.new(start_id, [move("d2", "d4"), move("d7", "d5")]),
        GameStart.standard(),
        %{"white" => "Magnus Carlsen", "black" => "Opponent", "result" => "0-1"}
      )

    {:ok, _other} =
      GameRecords.create(
        "record-other",
        GameContent.new(start_id, [move("e2", "e4"), move("c7", "c5")]),
        GameStart.standard(),
        %{"white" => "Somebody Else", "black" => "Opponent", "result" => "1-0"}
      )

    record_query =
      GameRecordQuery.all([
        GameRecordQuery.any([
          GameRecordQuery.metadata_value_contains("white", "carlsen"),
          GameRecordQuery.metadata_value_contains("black", "carlsen")
        ]),
        GameRecordQuery.metadata_contains(%{"result" => "1-0"})
      ])

    assert {:ok, %GameSearch.Page{entries: [{record, occurrence}], next: nil}} =
             GameSearch.page(Query.equivalent(after_e4), record_query, limit: 10)

    assert record.id == carlsen_win.id
    assert occurrence.game_id == carlsen_win.game_id

    # The substring match is case-insensitive and scopes to one colour.
    # Entries are occurrence-level: three records, each with an occurrence at
    # every position their game passes through (start + two moves).
    assert {:ok, %GameSearch.Page{entries: black_games}} =
             GameSearch.page(
               true,
               GameRecordQuery.metadata_value_contains("black", "OPPONENT"),
               limit: 10
             )

    assert length(black_games) == 9

    assert black_games
           |> Enum.map(fn {record, _occurrence} -> record.id end)
           |> Enum.uniq()
           |> length() == 3

    # Wildcard characters in names are literal text, not ILIKE wildcards.
    assert {:ok, %GameSearch.Page{entries: []}} =
             GameSearch.page(
               true,
               GameRecordQuery.metadata_value_contains("white", "100%"),
               limit: 10
             )
  end

  test "pages the joined result relation without duplicates or omissions" do
    {
      position_id,
      game_id
    } =
      stored_game(Position.starting_position())

    records =
      Enum.map(
        1..5,
        fn index ->
          record =
            GameRecord.new(
              "record-#{index}",
              game_id,
              %{
                "index" => index
              }
            )

          assert :ok =
                   GameRecordStore.insert(record)

          record
        end
      )

    assert {
             :ok,
             %GameSearch.Page{
               entries: first_page,
               next: first_cursor
             }
           } =
             GameSearch.page(
               Query.match_all(),
               limit: 2
             )

    assert %GameSearch.Cursor{} =
             first_cursor

    assert {
             :ok,
             %GameSearch.Page{
               entries: second_page,
               next: second_cursor
             }
           } =
             GameSearch.page(
               Query.match_all(),
               limit: 2,
               cursor: first_cursor
             )

    assert %GameSearch.Cursor{} =
             second_cursor

    assert {
             :ok,
             %GameSearch.Page{
               entries: third_page,
               next: nil
             }
           } =
             GameSearch.page(
               Query.match_all(),
               limit: 2,
               cursor: second_cursor
             )

    matches =
      first_page ++
        second_page ++
        third_page

    assert Enum.map(
             matches,
             fn {record, occurrence} ->
               {
                 record,
                 occurrence.game_id,
                 occurrence.ply,
                 occurrence.position_id
               }
             end
           ) ==
             Enum.map(
               records,
               fn record ->
                 {
                   record,
                   game_id,
                   0,
                   position_id
                 }
               end
             )
  end

  test "limit applies to actual search results rather than candidate positions" do
    records =
      Enum.map(
        1..5,
        fn index ->
          position =
            if index == 1 do
              Position.starting_position()
            else
              position_after_pawn_move(index)
            end

          {
            _position_id,
            game_id
          } =
            stored_game(position)

          excluded =
            GameRecord.new(
              "excluded-#{index}",
              game_id,
              %{
                "white" => "Other Player"
              }
            )

          matching =
            GameRecord.new(
              "matching-#{index}",
              game_id,
              %{
                "white" => "Magnus Carlsen"
              }
            )

          assert :ok =
                   GameRecordStore.insert(excluded)

          assert :ok =
                   GameRecordStore.insert(matching)

          matching
        end
      )

    query =
      GameRecordQuery.metadata_contains(%{
        "white" => "Magnus Carlsen"
      })

    assert {
             :ok,
             %GameSearch.Page{
               entries: first_page,
               next: cursor
             }
           } =
             GameSearch.page(
               Query.match_all(),
               query,
               limit: 3
             )

    assert length(first_page) ==
             3

    assert %GameSearch.Cursor{} =
             cursor

    assert {
             :ok,
             %GameSearch.Page{
               entries: second_page,
               next: nil
             }
           } =
             GameSearch.page(
               Query.match_all(),
               query,
               limit: 3,
               cursor: cursor
             )

    assert Enum.map(
             first_page ++ second_page,
             fn {record, _occurrence} ->
               record
             end
           ) ==
             records
  end

  test "excludes rows inserted after the first page snapshot" do
    first_position =
      Position.starting_position()

    {
      first_position_id,
      first_game_id
    } =
      stored_game(first_position)

    first =
      GameRecord.new(
        "record-1",
        first_game_id
      )

    second =
      GameRecord.new(
        "record-2",
        first_game_id
      )

    assert :ok =
             GameRecordStore.insert(first)

    assert :ok =
             GameRecordStore.insert(second)

    assert {
             :ok,
             %GameSearch.Page{
               entries: [
                 {
                   ^first,
                   first_occurrence
                 }
               ],
               next: cursor
             }
           } =
             GameSearch.page(
               Query.match_all(),
               limit: 1
             )

    assert first_occurrence.position_id ==
             first_position_id

    later_record =
      GameRecord.new(
        "record-3",
        first_game_id
      )

    assert :ok =
             GameRecordStore.insert(later_record)

    {:ok, second_position} =
      Position.apply_move(
        first_position,
        move(
          "e2",
          "e4"
        )
      )

    {
      _second_position_id,
      second_game_id
    } =
      stored_game(second_position)

    later_game_record =
      GameRecord.new(
        "record-4",
        second_game_id
      )

    assert :ok =
             GameRecordStore.insert(later_game_record)

    assert {
             :ok,
             %GameSearch.Page{
               entries: [
                 {
                   ^second,
                   second_occurrence
                 }
               ],
               next: nil
             }
           } =
             GameSearch.page(
               Query.match_all(),
               limit: 10,
               cursor: cursor
             )

    assert second_occurrence.position_id ==
             first_position_id
  end

  test "skips matching positions without concrete game results" do
    first_position =
      Position.starting_position()

    {:ok, second_position} =
      Position.apply_move(
        first_position,
        move(
          "e2",
          "e4"
        )
      )

    first_position_id =
      PositionStore.append(first_position)

    {
      second_position_id,
      game_id
    } =
      stored_game(second_position)

    record =
      GameRecord.new(
        "record-1",
        game_id
      )

    assert :ok =
             GameRecordStore.insert(record)

    assert {
             :ok,
             %GameSearch.Page{
               entries: [
                 {
                   ^record,
                   occurrence
                 }
               ],
               next: nil
             }
           } =
             GameSearch.page(
               Query.match_all(),
               limit: 10
             )

    assert occurrence.position_id ==
             second_position_id

    refute occurrence.position_id ==
             first_position_id
  end

  test "game-only searches page newest-first with one row per record" do
    {_position_id, game_id} =
      stored_game(Position.starting_position())

    for {record_id, date} <- [
          {"dated-oldest", "2026.09.01"},
          {"dated-newest", "2026.09.05"},
          {"dated-middle", "2026.09.03"},
          {"undated", nil}
        ] do
      metadata =
        if date,
          do: %{"white" => "Player", "date" => date},
          else: %{"white" => "Player"}

      assert :ok =
               GameRecordStore.insert(
                 GameRecord.new(
                   record_id,
                   game_id,
                   metadata
                 )
               )
    end

    {:ok, first_page} =
      GameSearch.page(
        Query.match_all(),
        GameRecordQuery.match_all(),
        limit: 2,
        sort: :date_desc
      )

    assert Enum.map(first_page.entries, fn {record, _occurrence} -> record.id end) == [
             "dated-newest",
             "dated-middle"
           ]

    assert %GameSearch.Cursor{} = first_page.next

    {:ok, second_page} =
      GameSearch.page(
        Query.match_all(),
        GameRecordQuery.match_all(),
        limit: 2,
        cursor: first_page.next,
        sort: :date_desc
      )

    # The undated record honestly sorts last; the corpus is fully paged.
    assert Enum.map(second_page.entries, fn {record, _occurrence} -> record.id end) == [
             "dated-oldest",
             "undated"
           ]

    assert second_page.next == nil

    # One row per record, with the first occurrence joined for the preview.
    for {record, occurrence} <- first_page.entries ++ second_page.entries do
      assert %GameOccurrence{} = occurrence
      assert occurrence.game_id == record.game_id
    end
  end

  test "date-sorted pages exclude rows inserted after the first page snapshot" do
    {_position_id, game_id} =
      stored_game(Position.starting_position())

    for {record_id, date} <- [
          {"old", "2026.09.01"},
          {"new", "2026.09.05"}
        ] do
      assert :ok =
               GameRecordStore.insert(
                 GameRecord.new(
                   record_id,
                   game_id,
                   %{"date" => date}
                 )
               )
    end

    {:ok, first_page} =
      GameSearch.page(
        Query.match_all(),
        GameRecordQuery.match_all(),
        limit: 1,
        sort: :date_desc
      )

    assert [{first_record, _occurrence}] = first_page.entries
    assert first_record.id == "new"

    assert :ok =
             GameRecordStore.insert(
               GameRecord.new(
                 "late",
                 game_id,
                 %{"date" => "2026.09.09"}
               )
             )

    {:ok, second_page} =
      GameSearch.page(
        Query.match_all(),
        GameRecordQuery.match_all(),
        limit: 1,
        cursor: first_page.next,
        sort: :date_desc
      )

    assert [{second_record, _occurrence}] = second_page.entries
    assert second_record.id == "old"
  end

  test "date sort with a position predicate is an explicit error" do
    assert GameSearch.page(
             Query.equivalent(Position.starting_position()),
             GameRecordQuery.match_all(),
             limit: 5,
             sort: :date_desc
           ) == {:error, :unsupported_sort}
  end

  test "an insertion-order cursor is not valid for a date-sorted search" do
    insertion_cursor = %GameSearch.Cursor{
      maximum_position_id: 1,
      maximum_occurrence_id: 1,
      maximum_record_row_id: 1,
      last_position_id: 1,
      last_occurrence_id: 1,
      last_record_row_id: 1
    }

    assert GameSearch.page(
             Query.match_all(),
             GameRecordQuery.match_all(),
             limit: 5,
             cursor: insertion_cursor,
             sort: :date_desc
           ) == {:error, :invalid_cursor}
  end

  test "searches positions by digest atoms" do
    first_position =
      Position.starting_position()

    {
      _first_position_id,
      first_game_id
    } =
      stored_game(first_position)

    record =
      GameRecord.new(
        "digest-record",
        first_game_id,
        %{"white" => "Player"}
      )

    assert :ok =
             GameRecordStore.insert(record)

    # The digest of the start position exists once it is stored.
    assert {:ok, _ids} =
             Analysis.PositionDigests.store_position_id(PositionStore.append(first_position))

    {:ok, page} =
      GameSearch.page(
        Query.digests(["material.signature:w:Q1R2B2N2P8"]),
        GameRecordQuery.match_all(),
        limit: 10
      )

    assert [{found_record, _occurrence}] = page.entries
    assert found_record.id == "digest-record"

    # An atom the dictionary does not know matches no position at all.
    {:ok, empty_page} =
      GameSearch.page(
        Query.digests(["material.signature:w:Q1R2B2N2P8", "test.atom.unregistered"]),
        GameRecordQuery.match_all(),
        limit: 10
      )

    assert empty_page.entries == []
  end

  test "color-swapped and mirrored exact searches find the transformed position" do
    alias Chess.Notation.FEN

    # No castling rights, so the transformed positions are valid positions
    # too. White pawn e4, black pawn e5, white king e1, black king e8.
    {:ok, %{position: original}} =
      FEN.parse("4k3/8/8/4p3/4P3/8/8/4K3 w - - 0 1")

    color_swapped = Position.color_swapped(original)
    mirrored = Position.file_reflected(original)

    {_swapped_position_id, swapped_game_id} =
      stored_game(color_swapped)

    {_mirrored_position_id, mirrored_game_id} =
      stored_game(mirrored)

    swapped_record =
      GameRecord.new(
        "swapped-record",
        swapped_game_id,
        %{"white" => "Player"}
      )

    mirrored_record =
      GameRecord.new(
        "mirrored-record",
        mirrored_game_id,
        %{"white" => "Player"}
      )

    for record <- [swapped_record, mirrored_record] do
      assert :ok =
               GameRecordStore.insert(record)
    end

    # The color-swapped search matches both the original and the swap.
    {:ok, page} =
      GameSearch.page(
        Query.any([
          Query.equivalent(original),
          Query.equivalent(color_swapped)
        ]),
        GameRecordQuery.match_all(),
        limit: 10
      )

    assert Enum.map(page.entries, fn {record, _occurrence} -> record.id end) ==
             ["swapped-record"]

    # The mirrored search matches the mirror image.
    {:ok, mirrored_page} =
      GameSearch.page(
        Query.any([
          Query.equivalent(original),
          Query.equivalent(mirrored)
        ]),
        GameRecordQuery.match_all(),
        limit: 10
      )

    assert Enum.map(mirrored_page.entries, fn {record, _occurrence} -> record.id end) ==
             ["mirrored-record"]
  end

  test "the search span reports the search shape" do
    parent = self()

    :telemetry.attach(
      "search-probe",
      [:openchesslab, :search, :page, :stop],
      fn _event, _measurements, metadata, _config ->
        send(parent, {:search_type, metadata.search_type})
      end,
      nil
    )

    GameSearch.page(Query.match_all(), limit: 1)
    assert_received {:search_type, :games}

    GameSearch.page(Query.equivalent(Position.starting_position()), limit: 1)
    assert_received {:search_type, :exact}

    GameSearch.page(Query.digests(["test.atom.probe"]), limit: 1)
    assert_received {:search_type, :digest}

    GameSearch.page(Query.pawn_structure(Position.starting_position()), limit: 1)
    assert_received {:search_type, :structure}

    GameSearch.page(
      Query.all([
        Query.pawn_structure(Position.starting_position()),
        Query.digests(["test.atom.probe"])
      ]),
      limit: 1
    )

    assert_received {:search_type, :digest}

    :telemetry.detach("search-probe")
  end

  test "similar search ranks by shared atoms within the structural neighborhood" do
    alias Chess.Square

    query_position =
      Position.new()
      |> Position.put_piece(Square.from_algebraic("d4"), {:white, :pawn})
      |> Position.put_piece(Square.from_algebraic("d5"), {:black, :pawn})
      |> Position.put_piece(Square.from_algebraic("e1"), {:white, :king})
      |> Position.put_piece(Square.from_algebraic("e8"), {:black, :king})

    # Same pawn skeleton within one structural edit and the same material.
    shifted_position =
      Position.new()
      |> Position.put_piece(Square.from_algebraic("d4"), {:white, :pawn})
      |> Position.put_piece(Square.from_algebraic("d6"), {:black, :pawn})
      |> Position.put_piece(Square.from_algebraic("e1"), {:white, :king})
      |> Position.put_piece(Square.from_algebraic("e8"), {:black, :king})

    # Different material: the white rook changes the material signature.
    richer_position =
      query_position
      |> Position.put_piece(Square.from_algebraic("a1"), {:white, :rook})

    # Outside the structural neighborhood (both pawns elsewhere).
    distant_position =
      Position.new()
      |> Position.put_piece(Square.from_algebraic("a2"), {:white, :pawn})
      |> Position.put_piece(Square.from_algebraic("h7"), {:black, :pawn})
      |> Position.put_piece(Square.from_algebraic("e1"), {:white, :king})
      |> Position.put_piece(Square.from_algebraic("e8"), {:black, :king})

    games =
      for {name, position} <- [
            {"same", query_position},
            {"shifted", shifted_position},
            {"richer", richer_position},
            {"distant", distant_position}
          ] do
        {position_id, game_id} = stored_game(position)
        {:ok, _ids} = Analysis.PositionDigests.store_position_id(position_id)

        assert :ok =
                 GameRecordStore.insert(GameRecord.new(name, game_id, %{"white" => "Player"}))

        name
      end

    assert games == ["same", "shifted", "richer", "distant"]

    {:ok, page} =
      GameSearch.similar(
        query_position,
        GameRecordQuery.match_all(),
        limit: 10
      )

    assert Enum.map(page.entries, fn {record, _occurrence, _shared} -> record.id end) ==
             ["same", "shifted"]

    # Identical shares every atom; the shifted twin shares fewer.
    assert [same_shared, shifted_shared] =
             Enum.map(page.entries, fn {_record, _occurrence, shared} -> shared end)

    assert same_shared > shifted_shared

    # Keyset paging continues past the top hit.
    {:ok, first_page} =
      GameSearch.similar(
        query_position,
        GameRecordQuery.match_all(),
        limit: 1
      )

    assert [{first_record, _occurrence, _shared}] = first_page.entries
    assert first_record.id == "same"

    {:ok, second_page} =
      GameSearch.similar(
        query_position,
        GameRecordQuery.match_all(),
        limit: 1,
        cursor: first_page.next
      )

    assert [{second_record, _occurrence, _shared}] = second_page.entries
    assert second_record.id == "shifted"
    assert second_page.next == nil
  end

  test "match-none queries return an empty page without querying PostgreSQL" do
    {
      position_result,
      position_query_count
    } =
      query_count(fn ->
        GameSearch.page(
          Query.match_none(),
          limit: 10
        )
      end)

    assert position_result ==
             {
               :ok,
               %GameSearch.Page{
                 entries: [],
                 next: nil
               }
             }

    assert position_query_count ==
             0

    {
      record_result,
      record_query_count
    } =
      query_count(fn ->
        GameSearch.page(
          Query.match_all(),
          GameRecordQuery.match_none(),
          limit: 10
        )
      end)

    assert record_result ==
             {
               :ok,
               %GameSearch.Page{
                 entries: [],
                 next: nil
               }
             }

    assert record_query_count ==
             0
  end

  test "requires a positive bounded page limit" do
    assert GameSearch.page(
             Query.match_all(),
             []
           ) ==
             {:error, :missing_limit}

    assert GameSearch.page(
             Query.match_all(),
             limit: 0
           ) ==
             {:error, :invalid_limit}

    assert GameSearch.page(
             Query.match_all(),
             limit: -1
           ) ==
             {:error, :invalid_limit}
  end

  test "rejects invalid cursor values" do
    assert GameSearch.page(
             Query.match_all(),
             limit: 10,
             cursor: make_ref()
           ) ==
             {:error, :invalid_cursor}
  end

  def handle_query(_event, _measurements, _metadata, parent) do
    send(
      parent,
      :game_search_query
    )

    :ok
  end

  defp stored_game(position) do
    position_id =
      PositionStore.append(position)

    assert is_integer(position_id)
    assert position_id > 0

    content =
      GameContent.new(position_id)

    {:ok, fingerprint} =
      GameFingerprint.for_content(content)

    assert {:ok, game_id} =
             GameStore.put(
               fingerprint,
               content,
               [
                 position_id
               ]
             )

    {
      position_id,
      game_id
    }
  end

  defp query_count(fun) when is_function(fun, 0) do
    event =
      Repo.config()
      |> Keyword.fetch!(:telemetry_prefix)
      |> Kernel.++([:query])

    handler_id = {
      __MODULE__,
      make_ref()
    }

    :ok =
      :telemetry.attach(
        handler_id,
        event,
        &__MODULE__.handle_query/4,
        self()
      )

    try do
      result =
        fun.()

      {
        result,
        drain_query_count(0)
      }
    after
      :telemetry.detach(handler_id)

      drain_query_count(0)
    end
  end

  defp drain_query_count(count) do
    receive do
      :game_search_query ->
        drain_query_count(count + 1)
    after
      0 ->
        count
    end
  end

  defp position_after_pawn_move(index) do
    file =
      Enum.at(
        [
          "a",
          "b",
          "c",
          "d",
          "e",
          "f",
          "g",
          "h"
        ],
        index - 2
      )

    {:ok, position} =
      Position.apply_move(
        Position.starting_position(),
        move(
          "#{file}2",
          "#{file}3"
        )
      )

    position
  end

  defp move(from, to) do
    Move.new(
      Square.from_algebraic(from),
      Square.from_algebraic(to)
    )
  end
end
