defmodule Analysis.PostgresGameStoreWriteShapeTest do
  use ExUnit.Case, async: false

  alias Analysis.GameContent
  alias Analysis.GameFingerprint
  alias Analysis.GameStore
  alias Analysis.PositionStore
  alias Chess.Move
  alias Chess.Position
  alias Chess.Square
  alias OpenChessLab.Repo

  @moduletag postgres: true

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

  test "inserts a new canonical game and its occurrences in one statement" do
    {
      content,
      position_ids
    } =
      one_move_game(
        "e2",
        "e4"
      )

    fingerprint =
      fingerprint(content)

    queries =
      capture_queries(fn ->
        assert {:ok, game_id} =
                 GameStore.put(
                   fingerprint,
                   content,
                   position_ids
                 )

        assert is_integer(game_id)
        assert game_id > 0
      end)

    normalized_queries =
      Enum.map(
        queries,
        &normalize_query/1
      )

    combined_writes =
      Enum.filter(
        normalized_queries,
        &String.starts_with?(
          &1,
          "WITH inserted_game AS"
        )
      )

    assert length(combined_writes) ==
             1

    [combined_write] =
      combined_writes

    assert String.contains?(
             combined_write,
             "INSERT INTO games"
           )

    assert String.contains?(
             combined_write,
             "INSERT INTO game_occurrences"
           )

    refute Enum.any?(
             normalized_queries,
             &String.starts_with?(
               &1,
               "INSERT INTO games"
             )
           )

    refute Enum.any?(
             normalized_queries,
             &String.starts_with?(
               &1,
               "INSERT INTO game_occurrences"
             )
           )

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

  defp one_move_game(from, to) do
    initial_position =
      Position.starting_position()

    initial_position_id =
      stored_position_id(initial_position)

    move =
      move(
        from,
        to
      )

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
    position_id =
      PositionStore.append(position)

    assert is_integer(position_id)
    assert position_id > 0

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

  defp capture_queries(fun) do
    event =
      Repo.config()
      |> Keyword.fetch!(:telemetry_prefix)
      |> Kernel.++([:query])

    handler_id =
      {
        __MODULE__,
        make_ref()
      }

    parent =
      self()

    :ok =
      :telemetry.attach(
        handler_id,
        event,
        fn _event, _measurements, metadata, parent ->
          send(
            parent,
            {
              :captured_query,
              metadata.query
            }
          )
        end,
        parent
      )

    try do
      fun.()
      drain_queries([])
    after
      :telemetry.detach(handler_id)
    end
  end

  defp drain_queries(queries) do
    receive do
      {
        :captured_query,
        query
      } ->
        drain_queries([
          query
          | queries
        ])
    after
      0 ->
        Enum.reverse(queries)
    end
  end

  defp normalize_query(query) do
    query
    |> String.replace(
      ~r/\s+/,
      " "
    )
    |> String.trim()
  end
end
