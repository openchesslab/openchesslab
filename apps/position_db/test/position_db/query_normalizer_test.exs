defmodule PositionDB.QueryNormalizerTest do
  use ExUnit.Case, async: true

  alias PositionDB.Query
  alias PositionDB.QueryNormalizer

  describe "normalize/1" do
    test "leaves property queries unchanged" do
      query = Query.property(:open_files, :e)

      assert QueryNormalizer.normalize(query) == query
    end

    test "normalizes NOT recursively" do
      query =
        Query.negate(
          Query.all([
            Query.property(:open_files, :e)
          ])
        )

      assert QueryNormalizer.normalize(query) ==
               Query.negate(Query.property(:open_files, :e))
    end

    test "flattens nested AND expressions" do
      query =
        Query.all([
          Query.property(:open_files, :a),
          Query.all([
            Query.property(:open_files, :b),
            Query.all([
              Query.property(:open_files, :c)
            ])
          ])
        ])

      assert QueryNormalizer.normalize(query) ==
               Query.all([
                 Query.property(:open_files, :a),
                 Query.property(:open_files, :b),
                 Query.property(:open_files, :c)
               ])
    end

    test "flattens nested OR expressions" do
      query =
        Query.any([
          Query.property(:open_files, :a),
          Query.any([
            Query.property(:open_files, :b),
            Query.any([
              Query.property(:open_files, :c)
            ])
          ])
        ])

      assert QueryNormalizer.normalize(query) ==
               Query.any([
                 Query.property(:open_files, :a),
                 Query.property(:open_files, :b),
                 Query.property(:open_files, :c)
               ])
    end

    test "reduces single-element AND" do
      query =
        Query.all([
          Query.property(:open_files, :e)
        ])

      assert QueryNormalizer.normalize(query) ==
               Query.property(:open_files, :e)
    end

    test "reduces single-element OR" do
      query =
        Query.any([
          Query.property(:open_files, :e)
        ])

      assert QueryNormalizer.normalize(query) ==
               Query.property(:open_files, :e)
    end

    test "removes duplicate AND expressions" do
      query =
        Query.all([
          Query.property(:open_files, :e),
          Query.property(:open_files, :d),
          Query.property(:open_files, :e)
        ])

      assert QueryNormalizer.normalize(query) ==
               Query.all([
                 Query.property(:open_files, :e),
                 Query.property(:open_files, :d)
               ])
    end

    test "removes duplicate OR expressions" do
      query =
        Query.any([
          Query.property(:open_files, :e),
          Query.property(:open_files, :d),
          Query.property(:open_files, :e)
        ])

      assert QueryNormalizer.normalize(query) ==
               Query.any([
                 Query.property(:open_files, :e),
                 Query.property(:open_files, :d)
               ])
    end
  end

  test "normalizes empty AND to TRUE" do
    assert QueryNormalizer.normalize(Query.all([])) == Query.match_all()
  end

  test "normalizes empty OR to FALSE" do
    assert QueryNormalizer.normalize(Query.any([])) == Query.match_none()
  end

  test "removes TRUE from AND" do
    query =
      Query.all([
        Query.property(:open_files, :e),
        Query.match_all()
      ])

    assert QueryNormalizer.normalize(query) ==
             Query.property(:open_files, :e)
  end

  test "removes FALSE from OR" do
    query =
      Query.any([
        Query.property(:open_files, :e),
        Query.match_none()
      ])

    assert QueryNormalizer.normalize(query) ==
             Query.property(:open_files, :e)
  end

  test "reduces AND containing FALSE to FALSE" do
    query =
      Query.all([
        Query.property(:open_files, :e),
        Query.match_none(),
        Query.property(:open_files, :e)
      ])

    assert QueryNormalizer.normalize(query) == Query.match_none()
  end

  test "reduces OR containing TRUE to TRUE" do
    query =
      Query.any([
        Query.property(:open_files, :e),
        Query.match_all(),
        Query.property(:open_files, :e)
      ])

    assert QueryNormalizer.normalize(query) == Query.match_all()
  end

  test "negates TRUE to FALSE" do
    assert QueryNormalizer.normalize(Query.negate(Query.match_all())) == Query.match_none()
  end

  test "negates FALSE to TRUE" do
    assert QueryNormalizer.normalize(Query.negate(Query.match_none())) == Query.match_all()
  end

  test "eliminates double negation" do
    query =
      Query.negate(Query.negate(Query.property(:open_files, :e)))

    assert QueryNormalizer.normalize(query) ==
             Query.property(:open_files, :e)
  end

  test "normalizes nested boolean expressions" do
    query =
      Query.all([
        Query.match_all(),
        Query.all([
          Query.property(:open_files, :e),
          Query.negate(Query.match_none())
        ])
      ])

    assert QueryNormalizer.normalize(query) ==
             Query.property(:open_files, :e)
  end

  test "AND of a query and its negation becomes false" do
    query =
      Query.all([
        Query.property(:open_files, :e),
        Query.negate(Query.property(:open_files, :e))
      ])

    assert QueryNormalizer.normalize(query) == Query.match_none()
  end

  test "AND of a negation and its query becomes false" do
    query =
      Query.all([
        Query.negate(Query.property(:open_files, :e)),
        Query.property(:open_files, :e)
      ])

    assert QueryNormalizer.normalize(query) == Query.match_none()
  end

  test "OR of a query and its negation becomes true" do
    query =
      Query.any([
        Query.property(:open_files, :e),
        Query.negate(Query.property(:open_files, :e))
      ])

    assert QueryNormalizer.normalize(query) == Query.match_all()
  end

  test "OR of a negation and its query becomes true" do
    query =
      Query.any([
        Query.negate(Query.property(:open_files, :e)),
        Query.property(:open_files, :e)
      ])

    assert QueryNormalizer.normalize(query) == Query.match_all()
  end

  test "detects complements after normalization" do
    query =
      Query.all([
        Query.all([
          Query.property(:open_files, :e)
        ]),
        Query.negate(Query.property(:open_files, :e))
      ])

    assert QueryNormalizer.normalize(query) == Query.match_none()
  end

  test "leaves equivalent queries unchanged" do
    position = :position
    query = Query.equivalent(position)

    assert QueryNormalizer.normalize(query) == query
  end
end
