defmodule Analysis.PositionQueryNormalizerTest do
  use ExUnit.Case, async: true

  alias Analysis.PositionQuery
  alias Analysis.PositionQueryNormalizer

  describe "normalize/1" do
    test "leaves property queries unchanged" do
      query =
        PositionQuery.property(
          :open_files,
          :e
        )

      assert PositionQueryNormalizer.normalize(query) ==
               query
    end

    test "normalizes NOT recursively" do
      query =
        PositionQuery.negate(
          PositionQuery.all([
            PositionQuery.property(
              :open_files,
              :e
            )
          ])
        )

      assert PositionQueryNormalizer.normalize(query) ==
               PositionQuery.negate(
                 PositionQuery.property(
                   :open_files,
                   :e
                 )
               )
    end

    test "flattens nested AND expressions" do
      query =
        PositionQuery.all([
          PositionQuery.property(
            :open_files,
            :a
          ),
          PositionQuery.all([
            PositionQuery.property(
              :open_files,
              :b
            ),
            PositionQuery.all([
              PositionQuery.property(
                :open_files,
                :c
              )
            ])
          ])
        ])

      assert PositionQueryNormalizer.normalize(query) ==
               PositionQuery.all([
                 PositionQuery.property(
                   :open_files,
                   :a
                 ),
                 PositionQuery.property(
                   :open_files,
                   :b
                 ),
                 PositionQuery.property(
                   :open_files,
                   :c
                 )
               ])
    end

    test "flattens nested OR expressions" do
      query =
        PositionQuery.any([
          PositionQuery.property(
            :open_files,
            :a
          ),
          PositionQuery.any([
            PositionQuery.property(
              :open_files,
              :b
            ),
            PositionQuery.any([
              PositionQuery.property(
                :open_files,
                :c
              )
            ])
          ])
        ])

      assert PositionQueryNormalizer.normalize(query) ==
               PositionQuery.any([
                 PositionQuery.property(
                   :open_files,
                   :a
                 ),
                 PositionQuery.property(
                   :open_files,
                   :b
                 ),
                 PositionQuery.property(
                   :open_files,
                   :c
                 )
               ])
    end

    test "reduces single-element AND" do
      query =
        PositionQuery.all([
          PositionQuery.property(
            :open_files,
            :e
          )
        ])

      assert PositionQueryNormalizer.normalize(query) ==
               PositionQuery.property(
                 :open_files,
                 :e
               )
    end

    test "reduces single-element OR" do
      query =
        PositionQuery.any([
          PositionQuery.property(
            :open_files,
            :e
          )
        ])

      assert PositionQueryNormalizer.normalize(query) ==
               PositionQuery.property(
                 :open_files,
                 :e
               )
    end

    test "removes duplicate AND expressions" do
      query =
        PositionQuery.all([
          PositionQuery.property(
            :open_files,
            :e
          ),
          PositionQuery.property(
            :open_files,
            :d
          ),
          PositionQuery.property(
            :open_files,
            :e
          )
        ])

      assert PositionQueryNormalizer.normalize(query) ==
               PositionQuery.all([
                 PositionQuery.property(
                   :open_files,
                   :e
                 ),
                 PositionQuery.property(
                   :open_files,
                   :d
                 )
               ])
    end

    test "removes duplicate OR expressions" do
      query =
        PositionQuery.any([
          PositionQuery.property(
            :open_files,
            :e
          ),
          PositionQuery.property(
            :open_files,
            :d
          ),
          PositionQuery.property(
            :open_files,
            :e
          )
        ])

      assert PositionQueryNormalizer.normalize(query) ==
               PositionQuery.any([
                 PositionQuery.property(
                   :open_files,
                   :e
                 ),
                 PositionQuery.property(
                   :open_files,
                   :d
                 )
               ])
    end
  end

  test "normalizes empty AND to TRUE" do
    assert PositionQueryNormalizer.normalize(PositionQuery.all([])) ==
             PositionQuery.match_all()
  end

  test "normalizes empty OR to FALSE" do
    assert PositionQueryNormalizer.normalize(PositionQuery.any([])) ==
             PositionQuery.match_none()
  end

  test "removes TRUE from AND" do
    query =
      PositionQuery.all([
        PositionQuery.property(
          :open_files,
          :e
        ),
        PositionQuery.match_all()
      ])

    assert PositionQueryNormalizer.normalize(query) ==
             PositionQuery.property(
               :open_files,
               :e
             )
  end

  test "removes FALSE from OR" do
    query =
      PositionQuery.any([
        PositionQuery.property(
          :open_files,
          :e
        ),
        PositionQuery.match_none()
      ])

    assert PositionQueryNormalizer.normalize(query) ==
             PositionQuery.property(
               :open_files,
               :e
             )
  end

  test "reduces AND containing FALSE to FALSE" do
    query =
      PositionQuery.all([
        PositionQuery.property(
          :open_files,
          :e
        ),
        PositionQuery.match_none(),
        PositionQuery.property(
          :open_files,
          :e
        )
      ])

    assert PositionQueryNormalizer.normalize(query) ==
             PositionQuery.match_none()
  end

  test "reduces OR containing TRUE to TRUE" do
    query =
      PositionQuery.any([
        PositionQuery.property(
          :open_files,
          :e
        ),
        PositionQuery.match_all(),
        PositionQuery.property(
          :open_files,
          :e
        )
      ])

    assert PositionQueryNormalizer.normalize(query) ==
             PositionQuery.match_all()
  end

  test "negates TRUE to FALSE" do
    assert PositionQueryNormalizer.normalize(PositionQuery.negate(PositionQuery.match_all())) ==
             PositionQuery.match_none()
  end

  test "negates FALSE to TRUE" do
    assert PositionQueryNormalizer.normalize(PositionQuery.negate(PositionQuery.match_none())) ==
             PositionQuery.match_all()
  end

  test "eliminates double negation" do
    query =
      PositionQuery.negate(
        PositionQuery.negate(
          PositionQuery.property(
            :open_files,
            :e
          )
        )
      )

    assert PositionQueryNormalizer.normalize(query) ==
             PositionQuery.property(
               :open_files,
               :e
             )
  end

  test "normalizes nested boolean expressions" do
    query =
      PositionQuery.all([
        PositionQuery.match_all(),
        PositionQuery.all([
          PositionQuery.property(
            :open_files,
            :e
          ),
          PositionQuery.negate(PositionQuery.match_none())
        ])
      ])

    assert PositionQueryNormalizer.normalize(query) ==
             PositionQuery.property(
               :open_files,
               :e
             )
  end

  test "AND of a query and its negation becomes false" do
    query =
      PositionQuery.all([
        PositionQuery.property(
          :open_files,
          :e
        ),
        PositionQuery.negate(
          PositionQuery.property(
            :open_files,
            :e
          )
        )
      ])

    assert PositionQueryNormalizer.normalize(query) ==
             PositionQuery.match_none()
  end

  test "AND of a negation and its query becomes false" do
    query =
      PositionQuery.all([
        PositionQuery.negate(
          PositionQuery.property(
            :open_files,
            :e
          )
        ),
        PositionQuery.property(
          :open_files,
          :e
        )
      ])

    assert PositionQueryNormalizer.normalize(query) ==
             PositionQuery.match_none()
  end

  test "OR of a query and its negation becomes true" do
    query =
      PositionQuery.any([
        PositionQuery.property(
          :open_files,
          :e
        ),
        PositionQuery.negate(
          PositionQuery.property(
            :open_files,
            :e
          )
        )
      ])

    assert PositionQueryNormalizer.normalize(query) ==
             PositionQuery.match_all()
  end

  test "OR of a negation and its query becomes true" do
    query =
      PositionQuery.any([
        PositionQuery.negate(
          PositionQuery.property(
            :open_files,
            :e
          )
        ),
        PositionQuery.property(
          :open_files,
          :e
        )
      ])

    assert PositionQueryNormalizer.normalize(query) ==
             PositionQuery.match_all()
  end

  test "detects complements after normalization" do
    query =
      PositionQuery.all([
        PositionQuery.all([
          PositionQuery.property(
            :open_files,
            :e
          )
        ]),
        PositionQuery.negate(
          PositionQuery.property(
            :open_files,
            :e
          )
        )
      ])

    assert PositionQueryNormalizer.normalize(query) ==
             PositionQuery.match_none()
  end

  test "leaves equivalent queries unchanged" do
    position =
      :position

    query =
      PositionQuery.equivalent(position)

    assert PositionQueryNormalizer.normalize(query) ==
             query
  end
end
