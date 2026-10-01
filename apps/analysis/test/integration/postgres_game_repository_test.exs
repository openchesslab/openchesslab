defmodule Analysis.PostgresGameRepositoryTest do
  use ExUnit.Case, async: false

  alias Analysis.GameContent
  alias Analysis.GameFingerprint
  alias Analysis.GameOccurrence
  alias Analysis.GameRepository.Postgres, as: GameRepository
  alias Analysis.PositionRepository.Postgres, as: PositionRepository
  alias Chess.Move
  alias Chess.Position
  alias Chess.Square
  alias OpenChessLab.Repo

  @moduletag postgres: true

  @collision_fingerprint :binary.copy(<<0xA5>>, 32)

  setup do
    Repo.query!(
      """
      TRUNCATE TABLE
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

  test "reports ready when PostgreSQL is reachable" do
    assert GameRepository.ready?()
  end

  test "stores canonical game content and occurrences transactionally" do
    {content, position_ids} =
      one_move_game("e2", "e4")

    fingerprint =
      fingerprint(content)

    assert GameRepository.put(
             fingerprint,
             content,
             position_ids
           ) ==
             {:ok, 1}

    assert GameRepository.get(1) ==
             {:ok, content}

    assert GameRepository.occurrences(1) ==
             {:ok,
              [
                GameOccurrence.new(
                  1,
                  1,
                  0,
                  Enum.at(position_ids, 0)
                ),
                GameOccurrence.new(
                  2,
                  1,
                  1,
                  Enum.at(position_ids, 1)
                )
              ]}

    assert GameRepository.get_occurrence(2) ==
             {:ok,
              GameOccurrence.new(
                2,
                1,
                1,
                Enum.at(position_ids, 1)
              )}
  end

  test "finds exact canonical content by fingerprint and full content" do
    {content, position_ids} =
      one_move_game("e2", "e4")

    fingerprint =
      fingerprint(content)

    assert {:ok, game_id} =
             GameRepository.put(
               fingerprint,
               content,
               position_ids
             )

    assert GameRepository.find(
             fingerprint,
             content
           ) ==
             {:ok, game_id}

    {different_content, _different_position_ids} =
      one_move_game("d2", "d4")

    assert GameRepository.find(
             fingerprint,
             different_content
           ) ==
             :not_found
  end

  test "reuses the durable id for duplicate exact canonical content" do
    {content, position_ids} =
      one_move_game("e2", "e4")

    fingerprint =
      fingerprint(content)

    assert {:ok, first_id} =
             GameRepository.put(
               fingerprint,
               content,
               position_ids
             )

    assert GameRepository.put(
             fingerprint,
             content,
             position_ids
           ) ==
             {:ok, first_id}

    assert [[1]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM games
               """,
               []
             ).rows

    assert [[2]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM game_occurrences
               """,
               []
             ).rows
  end

  test "concurrent inserts of the same exact game reuse one durable id" do
    {content, position_ids} =
      one_move_game("e2", "e4")

    fingerprint =
      fingerprint(content)

    results =
      1..2
      |> Enum.map(fn _index ->
        Task.async(fn ->
          GameRepository.put(
            fingerprint,
            content,
            position_ids
          )
        end)
      end)
      |> Task.await_many(5_000)

    assert [
             {:ok, first_game_id},
             {:ok, second_game_id}
           ] =
             results

    assert second_game_id ==
             first_game_id

    assert [[1]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM games
               """,
               []
             ).rows

    assert [[2]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM game_occurrences
               """,
               []
             ).rows
  end

  test "keeps distinct canonical games separate when fingerprints collide" do
    {first_content, first_position_ids} =
      one_move_game("e2", "e4")

    {second_content, second_position_ids} =
      one_move_game("d2", "d4")

    assert {:ok, first_id} =
             GameRepository.put(
               @collision_fingerprint,
               first_content,
               first_position_ids
             )

    assert {:ok, second_id} =
             GameRepository.put(
               @collision_fingerprint,
               second_content,
               second_position_ids
             )

    refute first_id == second_id

    assert GameRepository.find(
             @collision_fingerprint,
             first_content
           ) ==
             {:ok, first_id}

    assert GameRepository.find(
             @collision_fingerprint,
             second_content
           ) ==
             {:ok, second_id}

    assert [[2]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM games
               WHERE fingerprint = $1
               """,
               [@collision_fingerprint]
             ).rows
  end

  test "rejects occurrence lists inconsistent with canonical content" do
    initial_position_id =
      stored_position_id(Position.starting_position())

    content =
      GameContent.new(
        initial_position_id,
        [move("e2", "e4")]
      )

    fingerprint =
      fingerprint(content)

    assert GameRepository.put(
             fingerprint,
             content,
             [initial_position_id]
           ) ==
             {:error, :invalid_occurrences}

    other_position_id =
      stored_position_id(Position.new())

    empty_content =
      GameContent.new(initial_position_id)

    assert GameRepository.put(
             fingerprint(empty_content),
             empty_content,
             [other_position_id]
           ) ==
             {:error, :invalid_occurrences}

    assert [[0]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM games
               """,
               []
             ).rows
  end

  test "rolls back the game row when occurrence insertion violates the position foreign key" do
    initial_position =
      Position.starting_position()

    initial_position_id =
      stored_position_id(initial_position)

    content =
      GameContent.new(
        initial_position_id,
        [move("e2", "e4")]
      )

    missing_position_id =
      9_000_000_000

    assert {:error, _reason} =
             GameRepository.put(
               fingerprint(content),
               content,
               [
                 initial_position_id,
                 missing_position_id
               ]
             )

    assert [[0]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM games
               """,
               []
             ).rows

    assert [[0]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM game_occurrences
               """,
               []
             ).rows
  end

  test "enforces the position foreign key in game_occurrences" do
    {content, position_ids} =
      one_move_game("e2", "e4")

    assert {:ok, game_id} =
             GameRepository.put(
               fingerprint(content),
               content,
               position_ids
             )

    assert {:error, _reason} =
             Repo.query(
               """
               INSERT INTO game_occurrences (
                 game_id,
                 ply,
                 position_id
               )
               VALUES ($1, $2, $3)
               """,
               [
                 game_id,
                 99,
                 9_000_000_000
               ]
             )
  end

  test "enforces one occurrence per game and ply" do
    {content, position_ids} =
      one_move_game("e2", "e4")

    assert {:ok, game_id} =
             GameRepository.put(
               fingerprint(content),
               content,
               position_ids
             )

    assert {:error, _reason} =
             Repo.query(
               """
               INSERT INTO game_occurrences (
                 game_id,
                 ply,
                 position_id
               )
               VALUES ($1, $2, $3)
               """,
               [
                 game_id,
                 0,
                 hd(position_ids)
               ]
             )
  end

  test "pages occurrences by position with keyset cursors without duplicates or omissions" do
    initial_position =
      Position.starting_position()

    initial_position_id =
      stored_position_id(initial_position)

    games =
      [
        {"e2", "e4"},
        {"d2", "d4"},
        {"c2", "c4"}
      ]
      |> Enum.map(fn {from, to} ->
        put_one_move_game(
          initial_position,
          initial_position_id,
          from,
          to
        )
      end)

    assert {
             :ok,
             first_page,
             cursor
           } =
             GameRepository.occurrences_page(
               initial_position_id,
               2
             )

    assert %GameRepository.Cursor{} =
             cursor

    assert {
             :ok,
             second_page,
             :done
           } =
             GameRepository.next_occurrences_page(
               cursor,
               2
             )

    occurrences =
      first_page ++ second_page

    assert Enum.map(
             occurrences,
             & &1.id
           ) ==
             [1, 3, 5]

    assert Enum.map(
             occurrences,
             & &1.game_id
           ) ==
             Enum.map(
               games,
               &elem(&1, 0)
             )

    assert Enum.all?(
             occurrences,
             fn occurrence ->
               occurrence.ply == 0 and
                 occurrence.position_id == initial_position_id
             end
           )
  end

  test "does not include occurrences inserted after a scan starts" do
    initial_position =
      Position.starting_position()

    initial_position_id =
      stored_position_id(initial_position)

    {first_game_id, _first_final_position_id} =
      put_one_move_game(
        initial_position,
        initial_position_id,
        "e2",
        "e4"
      )

    {second_game_id, _second_final_position_id} =
      put_one_move_game(
        initial_position,
        initial_position_id,
        "d2",
        "d4"
      )

    assert {
             :ok,
             [first_occurrence],
             cursor
           } =
             GameRepository.occurrences_page(
               initial_position_id,
               1
             )

    assert first_occurrence.game_id ==
             first_game_id

    {third_game_id, _third_final_position_id} =
      put_one_move_game(
        initial_position,
        initial_position_id,
        "c2",
        "c4"
      )

    assert {
             :ok,
             [second_occurrence],
             :done
           } =
             GameRepository.next_occurrences_page(
               cursor,
               10
             )

    assert second_occurrence.game_id ==
             second_game_id

    refute second_occurrence.game_id ==
             third_game_id
  end

  test "returns an empty bounded page when a position has no occurrences" do
    position_id =
      stored_position_id(Position.starting_position())

    assert GameRepository.occurrences_page(
             position_id,
             10
           ) ==
             {
               :ok,
               [],
               :done
             }
  end

  test "returns not found for unknown game and occurrence ids" do
    assert GameRepository.get(999_999) ==
             :not_found

    assert GameRepository.occurrences(999_999) ==
             :not_found

    assert GameRepository.get_occurrence(999_999) ==
             :not_found
  end

  test "validates fingerprint size before writing" do
    position_id =
      stored_position_id(Position.starting_position())

    content =
      GameContent.new(position_id)

    assert GameRepository.put(
             <<1, 2, 3>>,
             content,
             [position_id]
           ) ==
             {:error, :invalid_fingerprint}

    assert [[0]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM games
               """,
               []
             ).rows
  end

  test "close_occurrences is a no-op for stateless cursors" do
    initial_position =
      Position.starting_position()

    initial_position_id =
      stored_position_id(initial_position)

    put_one_move_game(
      initial_position,
      initial_position_id,
      "e2",
      "e4"
    )

    put_one_move_game(
      initial_position,
      initial_position_id,
      "d2",
      "d4"
    )

    assert {
             :ok,
             [_occurrence],
             cursor
           } =
             GameRepository.occurrences_page(
               initial_position_id,
               1
             )

    assert :ok =
             GameRepository.close_occurrences(cursor)

    assert {
             :ok,
             [_occurrence],
             :done
           } =
             GameRepository.next_occurrences_page(
               cursor,
               1
             )

    assert GameRepository.next_occurrences_page(
             make_ref(),
             1
           ) ==
             {:error, :cursor_not_found}
  end

  defp put_one_move_game(initial_position, initial_position_id, from, to) do
    move =
      move(from, to)

    {:ok, final_position} =
      Position.apply_move(
        initial_position,
        move
      )

    final_position_id =
      stored_position_id(final_position)

    content =
      GameContent.new(
        initial_position_id,
        [move]
      )

    assert {:ok, game_id} =
             GameRepository.put(
               fingerprint(content),
               content,
               [
                 initial_position_id,
                 final_position_id
               ]
             )

    {
      game_id,
      final_position_id
    }
  end

  defp one_move_game(from, to) do
    initial_position =
      Position.starting_position()

    initial_position_id =
      stored_position_id(initial_position)

    move =
      move(from, to)

    {:ok, final_position} =
      Position.apply_move(
        initial_position,
        move
      )

    final_position_id =
      stored_position_id(final_position)

    {
      GameContent.new(
        initial_position_id,
        [move]
      ),
      [
        initial_position_id,
        final_position_id
      ]
    }
  end

  defp stored_position_id(position) do
    {:ok, position_id} =
      PositionRepository.put(position)

    position_id
  end

  defp fingerprint(content) do
    {:ok, fingerprint} =
      GameFingerprint.for_content(content)

    fingerprint
  end

  defp move(from, to) do
    Move.new(
      Square.from_algebraic(from),
      Square.from_algebraic(to)
    )
  end
end
