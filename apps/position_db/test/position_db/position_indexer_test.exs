defmodule PositionDB.PositionIndexerTest do
  use ExUnit.Case, async: true

  alias PositionDB.PositionIndexer

  test "derives scalar and list property values in configured order" do
    indexer =
      PositionIndexer.new([
        {:color, & &1.color},
        {:files, & &1.files}
      ])

    position = %{
      color: :white,
      files: [:a, :e]
    }

    assert PositionIndexer.properties_for(
             indexer,
             position
           ) ==
             [
               {:color, :white},
               {:files, :a},
               {:files, :e}
             ]
  end

  test "omits postings for an empty property value list" do
    indexer =
      PositionIndexer.new([
        {:files, & &1.files}
      ])

    assert PositionIndexer.properties_for(
             indexer,
             %{files: []}
           ) ==
             []
  end
end
