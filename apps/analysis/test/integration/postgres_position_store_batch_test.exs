defmodule Analysis.PostgresPositionStoreBatchTest do
  use ExUnit.Case, async: false

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
        position_features,
        positions
      RESTART IDENTITY
      CASCADE
      """,
      []
    )

    :ok
  end

  test "stores a position batch once and preserves occurrence order" do
    first =
      Position.starting_position()

    {:ok, second} =
      Position.apply_move(
        first,
        move(
          "e2",
          "e4"
        )
      )

    assert {:ok,
            [
              first_id,
              second_id,
              repeated_first_id
            ]} =
             PositionStore.append_many([
               first,
               second,
               first
             ])

    assert first_id ==
             repeated_first_id

    refute first_id ==
             second_id

    assert PositionStore.get(first_id) ==
             {:ok, first}

    assert PositionStore.get(second_id) ==
             {:ok, second}

    assert [[2]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM positions
               """,
               []
             ).rows

    assert [[2]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM position_features
               """,
               []
             ).rows
  end

  test "existing position batches use one insert and one id lookup without rewriting features" do
    first =
      Position.starting_position()

    {:ok, second} =
      Position.apply_move(
        first,
        move(
          "e2",
          "e4"
        )
      )

    assert {:ok, expected_ids} =
             PositionStore.append_many([
               first,
               second,
               first
             ])

    Repo.query!(
      """
      UPDATE position_features
      SET properties = '{}'::bytea[]
      """,
      []
    )

    queries =
      capture_queries(fn ->
        assert PositionStore.append_many([
                 first,
                 second,
                 first
               ]) ==
                 {:ok, expected_ids}
      end)

    normalized_queries =
      Enum.map(
        queries,
        &normalize_query/1
      )

    assert Enum.count(
             normalized_queries,
             &String.starts_with?(
               &1,
               "WITH inserted_positions AS"
             )
           ) ==
             1

    assert Enum.count(
             normalized_queries,
             &String.starts_with?(
               &1,
               "SELECT p.id FROM unnest"
             )
           ) ==
             1

    refute Enum.any?(
             normalized_queries,
             &String.starts_with?(
               &1,
               "INSERT INTO position_features"
             )
           )

    assert [
             [0],
             [0]
           ] =
             Repo.query!(
               """
               SELECT cardinality(properties)
               FROM position_features
               ORDER BY position_id
               """,
               []
             ).rows
  end

  test "concurrent batches reuse canonical positions even when input order differs" do
    first =
      Position.starting_position()

    {:ok, second} =
      Position.apply_move(
        first,
        move(
          "e2",
          "e4"
        )
      )

    tasks =
      Enum.map(
        1..10,
        fn index ->
          Task.async(fn ->
            positions =
              if rem(index, 2) == 0 do
                [
                  first,
                  second
                ]
              else
                [
                  second,
                  first
                ]
              end

            {
              positions,
              PositionStore.append_many(positions)
            }
          end)
        end
      )

    results =
      Task.await_many(
        tasks,
        5_000
      )

    Enum.each(
      results,
      fn
        {
          positions,
          {
            :ok,
            position_ids
          }
        } ->
          positions
          |> Enum.zip(position_ids)
          |> Enum.each(fn {position, position_id} ->
            assert PositionStore.find(position) ==
                     {:ok, position_id}
          end)
      end
    )

    assert [[2]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM positions
               """,
               []
             ).rows

    assert [[2]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM position_features
               """,
               []
             ).rows
  end

  test "new position batches insert positions and features together" do
    first =
      Position.starting_position()

    {:ok, second} =
      Position.apply_move(
        first,
        move(
          "e2",
          "e4"
        )
      )

    queries =
      capture_queries(fn ->
        assert {:ok, position_ids} =
                 PositionStore.append_many([
                   first,
                   second
                 ])

        assert length(position_ids) == 2
      end)

    normalized_queries =
      Enum.map(
        queries,
        &normalize_query/1
      )

    combined_inserts =
      Enum.filter(
        normalized_queries,
        &String.starts_with?(
          &1,
          "WITH inserted_positions AS"
        )
      )

    assert length(combined_inserts) == 1

    [combined_insert] =
      combined_inserts

    assert String.contains?(
             combined_insert,
             "INSERT INTO positions"
           )

    assert String.contains?(
             combined_insert,
             "INSERT INTO position_features"
           )

    assert Enum.count(
             normalized_queries,
             &String.starts_with?(
               &1,
               "SELECT p.id FROM unnest"
             )
           ) ==
             1

    refute Enum.any?(
             normalized_queries,
             &String.starts_with?(
               &1,
               "INSERT INTO position_features"
             )
           )

    assert [[2]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM positions
               """,
               []
             ).rows

    assert [[2]] =
             Repo.query!(
               """
               SELECT count(*)
               FROM position_features
               """,
               []
             ).rows
  end

  defp move(from, to) do
    Move.new(
      Square.from_algebraic(from),
      Square.from_algebraic(to)
    )
  end

  defp capture_queries(fun) do
    telemetry_prefix =
      Repo.config()
      |> Keyword.fetch!(:telemetry_prefix)

    event =
      telemetry_prefix ++
        [:query]

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
        drain_queries([query | queries])
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
