defmodule PositionDB.QueryTest do
  use ExUnit.Case, async: true

  alias PositionDB.Query

  test "builds property query" do
    assert Query.property(:open_files, :e) ==
             {:property, :open_files, :e}
  end

  test "builds equivalent query" do
    position = :position

    assert Query.equivalent(position) ==
             {:equivalent, position}
  end

  test "builds AND query" do
    queries = [
      Query.property(:open_files, :e),
      Query.equivalent(:position)
    ]

    assert Query.all(queries) ==
             {:and, queries}
  end

  test "builds OR query" do
    queries = [
      Query.property(:open_files, :e),
      Query.property(:open_files, :d)
    ]

    assert Query.any(queries) ==
             {:or, queries}
  end

  test "builds NOT query" do
    query = Query.property(:open_files, :e)

    assert Query.negate(query) ==
             {:not, query}
  end

  test "builds true query" do
    assert Query.match_all() == true
  end

  test "builds false query" do
    assert Query.match_none() == false
  end
end
