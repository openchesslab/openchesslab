defmodule Analysis.RoomInventoryTest do
  use ExUnit.Case, async: false

  alias Analysis.RoomInventory
  alias Analysis.Rooms
  alias Analysis.RoomStore
  alias OpenChessLab.Repo

  setup do
    prefix = "room-inventory-" <> Base.encode16(:crypto.strong_rand_bytes(8))
    old_empty = prefix <> "-old-empty"
    old_with_analysis = prefix <> "-old-with-analysis"
    recent_empty = prefix <> "-recent-empty"
    room_ids = [old_empty, old_with_analysis, recent_empty]

    Enum.each(room_ids, fn room_id ->
      assert :ok = RoomStore.create(room_id)
    end)

    on_exit(fn ->
      Enum.each(room_ids, &RoomStore.delete/1)
    end)

    Repo.query!(
      "UPDATE rooms SET created_at = now() - INTERVAL '40 days' WHERE id = ANY($1::text[])",
      [[old_empty, old_with_analysis]]
    )

    assert :ok = RoomStore.add_analysis(old_with_analysis, "analysis-" <> prefix)

    %{
      old_empty: old_empty,
      old_with_analysis: old_with_analysis,
      recent_empty: recent_empty
    }
  end

  test "reports counts of empty, occupied and old rooms without changing them", %{old_empty: id} do
    report = RoomInventory.summary(30)

    assert report.older_than_days == 30
    assert report.total_rooms >= 3
    assert report.rooms_with_analyses >= 1
    assert report.empty_rooms >= 2
    assert report.old_empty_rooms >= 1

    assert {:ok, %{id: ^id, analysis_ids: []}} = RoomStore.get(id)
  end

  test "lists old empty rooms, excluding recent and occupied rooms", context do
    candidates = RoomInventory.old_empty_rooms(30, 1_000)
    ids = Enum.map(candidates, & &1.id)

    assert context.old_empty in ids
    refute context.old_with_analysis in ids
    refute context.recent_empty in ids

    assert Enum.all?(candidates, &is_integer(&1.created_at_unix))
  end

  test "all newly created rooms have a creation timestamp", context do
    [[created_at]] =
      Repo.query!("SELECT created_at FROM rooms WHERE id = $1", [context.old_empty]).rows

    refute is_nil(created_at)
  end

  test "prunes old empty rooms while retaining recent and occupied rooms", context do
    deleted = Rooms.prune_old_empty_rooms(30, 1_000)

    assert context.old_empty in deleted
    assert :not_found = RoomStore.get(context.old_empty)
    assert {:ok, _room} = RoomStore.get(context.old_with_analysis)
    assert {:ok, _room} = RoomStore.get(context.recent_empty)
    refute context.old_with_analysis in deleted
    refute context.recent_empty in deleted
    assert RoomStore.prune_old_empty_rooms(30, 1_000) == []
  end

  test "pruning has a bounded batch size and validates arguments" do
    assert length(Rooms.prune_old_empty_rooms(30, 1)) <= 1

    assert_raise FunctionClauseError, fn -> RoomStore.prune_old_empty_rooms(-1, 10) end
    assert_raise FunctionClauseError, fn -> RoomStore.prune_old_empty_rooms(30, 1_001) end
  end

  test "limits the read-only candidate report" do
    assert length(RoomInventory.old_empty_rooms(30, 1)) <= 1
    assert_raise FunctionClauseError, fn -> RoomInventory.old_empty_rooms(30, 1_001) end
    assert_raise FunctionClauseError, fn -> RoomInventory.old_empty_rooms(-1, 1) end
  end
end
