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
end
