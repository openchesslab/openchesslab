defmodule Analysis.RoomTest do
  use ExUnit.Case, async: true

  alias Analysis.Room

  test "creates an empty room" do
    room = Room.new("room-1")

    assert Room.id(room) == "room-1"
    assert Room.analysis_ids(room) == []
  end

  test "adds an analysis" do
    room =
      "room-1"
      |> Room.new()
      |> Room.add_analysis("analysis-1")

    assert Room.analysis_ids(room) == ["analysis-1"]
    assert Room.has_analysis?(room, "analysis-1")
  end

  test "adds multiple analyses in order" do
    room =
      "room-1"
      |> Room.new()
      |> Room.add_analysis("analysis-1")
      |> Room.add_analysis("analysis-2")
      |> Room.add_analysis("analysis-3")

    assert Room.analysis_ids(room) ==
             ["analysis-1", "analysis-2", "analysis-3"]
  end

  test "adding the same analysis twice is idempotent" do
    room =
      "room-1"
      |> Room.new()
      |> Room.add_analysis("analysis-1")
      |> Room.add_analysis("analysis-1")

    assert Room.analysis_ids(room) == ["analysis-1"]
  end

  test "removes an analysis" do
    room =
      "room-1"
      |> Room.new()
      |> Room.add_analysis("analysis-1")
      |> Room.add_analysis("analysis-2")
      |> Room.remove_analysis("analysis-1")

    refute Room.has_analysis?(room, "analysis-1")
    assert Room.has_analysis?(room, "analysis-2")
    assert Room.analysis_ids(room) == ["analysis-2"]
  end

  test "removing an unknown analysis is idempotent" do
    room =
      "room-1"
      |> Room.new()
      |> Room.add_analysis("analysis-1")
      |> Room.remove_analysis("missing")

    assert Room.analysis_ids(room) == ["analysis-1"]
  end
end
