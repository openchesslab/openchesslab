defmodule PositionDB.QueryNormalizerTest do
  use ExUnit.Case, async: true

  alias PositionDB.QueryNormalizer

  describe "normalize/1" do
    test "leaves property queries unchanged" do
      query = {:property, :open_files, :e}

      assert QueryNormalizer.normalize(query) == query
    end

    test "normalizes NOT recursively" do
      query =
        {:not,
         {:and,
          [
            {:property, :open_files, :e}
          ]}}

      assert QueryNormalizer.normalize(query) ==
               {:not, {:property, :open_files, :e}}
    end

    test "flattens nested AND expressions" do
      query =
        {:and,
         [
           {:property, :open_files, :a},
           {:and,
            [
              {:property, :open_files, :b},
              {:and,
               [
                 {:property, :open_files, :c}
               ]}
            ]}
         ]}

      assert QueryNormalizer.normalize(query) ==
               {:and,
                [
                  {:property, :open_files, :a},
                  {:property, :open_files, :b},
                  {:property, :open_files, :c}
                ]}
    end

    test "flattens nested OR expressions" do
      query =
        {:or,
         [
           {:property, :open_files, :a},
           {:or,
            [
              {:property, :open_files, :b},
              {:or,
               [
                 {:property, :open_files, :c}
               ]}
            ]}
         ]}

      assert QueryNormalizer.normalize(query) ==
               {:or,
                [
                  {:property, :open_files, :a},
                  {:property, :open_files, :b},
                  {:property, :open_files, :c}
                ]}
    end

    test "reduces single-element AND" do
      query =
        {:and,
         [
           {:property, :open_files, :e}
         ]}

      assert QueryNormalizer.normalize(query) ==
               {:property, :open_files, :e}
    end

    test "reduces single-element OR" do
      query =
        {:or,
         [
           {:property, :open_files, :e}
         ]}

      assert QueryNormalizer.normalize(query) ==
               {:property, :open_files, :e}
    end

    test "removes duplicate AND expressions" do
      query =
        {:and,
         [
           {:property, :open_files, :e},
           {:property, :open_files, :d},
           {:property, :open_files, :e}
         ]}

      assert QueryNormalizer.normalize(query) ==
               {:and,
                [
                  {:property, :open_files, :e},
                  {:property, :open_files, :d}
                ]}
    end

    test "removes duplicate OR expressions" do
      query =
        {:or,
         [
           {:property, :open_files, :e},
           {:property, :open_files, :d},
           {:property, :open_files, :e}
         ]}

      assert QueryNormalizer.normalize(query) ==
               {:or,
                [
                  {:property, :open_files, :e},
                  {:property, :open_files, :d}
                ]}
    end
  end
end
