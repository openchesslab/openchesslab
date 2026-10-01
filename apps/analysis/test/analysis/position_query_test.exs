defmodule Analysis.PositionQueryTest do
  use ExUnit.Case, async: true

  alias Analysis.PositionQuery

  test "builds property query" do
    assert PositionQuery.property(
             :open_files,
             :e
           ) ==
             {
               :property,
               :open_files,
               :e
             }
  end

  test "builds equivalent query" do
    position =
      :position

    assert PositionQuery.equivalent(position) ==
             {
               :equivalent,
               position
             }
  end

  test "builds AND query" do
    queries = [
      PositionQuery.property(
        :open_files,
        :e
      ),
      PositionQuery.equivalent(:position)
    ]

    assert PositionQuery.all(queries) ==
             {
               :and,
               queries
             }
  end

  test "builds OR query" do
    queries = [
      PositionQuery.property(
        :open_files,
        :e
      ),
      PositionQuery.property(
        :open_files,
        :d
      )
    ]

    assert PositionQuery.any(queries) ==
             {
               :or,
               queries
             }
  end

  test "builds NOT query" do
    query =
      PositionQuery.property(
        :open_files,
        :e
      )

    assert PositionQuery.negate(query) ==
             {
               :not,
               query
             }
  end

  test "builds true query" do
    assert PositionQuery.match_all() ==
             true
  end

  test "builds false query" do
    assert PositionQuery.match_none() ==
             false
  end
end
