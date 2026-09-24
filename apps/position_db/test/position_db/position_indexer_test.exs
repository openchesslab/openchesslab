defmodule PositionDB.PositionIndexerTest do
  use ExUnit.Case, async: true

  alias PositionDB.PositionIndexer
  alias PositionDB.PropertyIndex

  defmodule TrackingBackend do
    @behaviour PositionDB.PropertyIndex.Backend

    @impl PositionDB.PropertyIndex.Backend
    def add(
          state,
          property,
          position_id
        ) do
      send(
        state.test_pid,
        {:add, property, position_id}
      )

      if property == state.fail_on do
        {:error, :disk_failure}
      else
        {:ok, state}
      end
    end

    @impl PositionDB.PropertyIndex.Backend
    def advance(
          state,
          position_id
        ) do
      send(
        state.test_pid,
        {:advance, position_id}
      )

      {:ok, state}
    end

    @impl PositionDB.PropertyIndex.Backend
    def lookup(
          _state,
          _property
        ) do
      {:ok, []}
    end

    @impl PositionDB.PropertyIndex.Backend
    def cardinality(
          _state,
          _property
        ) do
      {:ok, 0}
    end
  end

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

  test "advances progress after all properties for a position are indexed" do
    property_index =
      PropertyIndex.new(
        TrackingBackend,
        %{
          test_pid: self(),
          fail_on: nil
        }
      )

    indexer =
      PositionIndexer.new(
        [
          {:color, & &1.color},
          {:files, & &1.files}
        ],
        property_index
      )

    assert %PositionIndexer{} =
             PositionIndexer.index(
               indexer,
               7,
               %{
                 color: :white,
                 files: [:a, :e]
               }
             )

    assert_receive {:add, {:color, :white}, 7}
    assert_receive {:add, {:files, :a}, 7}
    assert_receive {:add, {:files, :e}, 7}
    assert_receive {:advance, 7}
  end

  test "does not advance progress when a property posting fails" do
    property_index =
      PropertyIndex.new(
        TrackingBackend,
        %{
          test_pid: self(),
          fail_on: {:selected, true}
        }
      )

    indexer =
      PositionIndexer.new(
        [
          {:color, & &1.color},
          {:selected, & &1.selected}
        ],
        property_index
      )

    assert PositionIndexer.index(
             indexer,
             8,
             %{
               color: :white,
               selected: true
             }
           ) ==
             {:error, :disk_failure}

    assert_receive {:add, {:color, :white}, 8}
    assert_receive {:add, {:selected, true}, 8}

    refute_receive {:advance, 8}
  end
end
