defmodule Analysis.GameRecordQueryTest do
  use ExUnit.Case, async: true

  alias Analysis.GameRecordQuery

  test "builds a metadata containment query" do
    assert GameRecordQuery.metadata_contains(%{
             "white" => "Magnus Carlsen",
             "event" => "Wijk aan Zee"
           }) ==
             {
               :metadata_contains,
               %{
                 "white" => "Magnus Carlsen",
                 "event" => "Wijk aan Zee"
               }
             }
  end

  test "supports match all and match none" do
    assert GameRecordQuery.match_all() ==
             true

    assert GameRecordQuery.match_none() ==
             false
  end

  test "builds substring and junction queries for the search UI" do
    assert GameRecordQuery.metadata_value_contains("white", "carlsen") ==
             {:metadata_value_contains, "white", "carlsen"}

    assert GameRecordQuery.all([true, GameRecordQuery.match_none()]) ==
             {:and, [true, false]}

    assert GameRecordQuery.any([GameRecordQuery.match_none()]) ==
             {:or, [false]}
  end

  test "rejects invalid metadata" do
    assert_raise ArgumentError, fn ->
      apply(
        GameRecordQuery,
        :metadata_contains,
        [
          %{
            white: "Magnus Carlsen"
          }
        ]
      )
    end
  end

  test "compiles closed, open and empty string ranges" do
    alias Analysis.GameRecordQuery.Postgres

    assert {:ok, sql, params, 4} =
             Postgres.compile_predicate(
               GameRecordQuery.metadata_value_between("date", "2026.01.01", "2026.12.31"),
               1
             )

    assert sql == "(gr.metadata ->> $1) >= $2 AND (gr.metadata ->> $1) <= $3"
    assert params == ["date", "2026.01.01", "2026.12.31"]

    assert {:ok, sql, params, 3} =
             Postgres.compile_predicate(
               GameRecordQuery.metadata_value_between("date", nil, "2026.12.31"),
               1
             )

    assert sql == "(gr.metadata ->> $1) <= $2"
    assert params == ["date", "2026.12.31"]

    assert {:ok, "TRUE", [], 1} =
             Postgres.compile_predicate(
               GameRecordQuery.metadata_value_between("date", nil, nil),
               1
             )
  end

  test "compiles numeric ranges behind a digit guard" do
    alias Analysis.GameRecordQuery.Postgres

    assert {:ok, sql, params, 3} =
             Postgres.compile_predicate(
               GameRecordQuery.metadata_int_between("white_elo", 2500, nil),
               1
             )

    assert sql == "(gr.metadata ->> $1) ~ '^[0-9]+$' AND (gr.metadata ->> $1)::int >= $2"
    assert params == ["white_elo", 2500]

    assert {:ok, sql, params, 10} =
             Postgres.compile_predicate(
               GameRecordQuery.metadata_int_between("black_elo", 2200, 2500),
               7
             )

    assert sql ==
             "(gr.metadata ->> $7) ~ '^[0-9]+$' AND (gr.metadata ->> $7)::int >= $8 AND (gr.metadata ->> $7)::int <= $9"

    assert params == ["black_elo", 2200, 2500]

    assert {:ok, "TRUE", [], 5} =
             Postgres.compile_predicate({:metadata_int_between, "white_elo", nil, nil}, 5)
  end
end
