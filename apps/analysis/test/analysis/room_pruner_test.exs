defmodule Analysis.RoomPrunerTest do
  use ExUnit.Case, async: false

  alias Analysis.RoomPruner
  alias Analysis.RoomStore
  alias OpenChessLab.Repo

  setup do
    prefix = "room-pruner-" <> Base.encode16(:crypto.strong_rand_bytes(8))
    old_empty = prefix <> "-old-empty"
    old_with_analysis = prefix <> "-old-with-analysis"
    recent_empty = prefix <> "-recent-empty"
    ids = [old_empty, old_with_analysis, recent_empty]

    Enum.each(ids, fn id -> assert :ok = RoomStore.create(id) end)
    on_exit(fn -> Enum.each(ids, &RoomStore.delete/1) end)

    Repo.query!(
      "UPDATE rooms SET created_at = now() - INTERVAL '40 days' WHERE id = ANY($1::text[])",
      [[old_empty, old_with_analysis]]
    )

    assert :ok = RoomStore.add_analysis(old_with_analysis, "analysis-" <> prefix)

    %{old_empty: old_empty, old_with_analysis: old_with_analysis, recent_empty: recent_empty}
  end

  test "scheduled pass removes old empty rooms but retains linked and recent rooms", context do
    pruner =
      start_supervised!({RoomPruner, initial_delay_ms: to_timeout(hour: 1)})

    # Trigger deterministically, without waiting for the production timer.
    send(pruner, :prune)
    _state = :sys.get_state(pruner)

    assert :not_found = RoomStore.get(context.old_empty)
    assert {:ok, _} = RoomStore.get(context.old_with_analysis)
    assert {:ok, _} = RoomStore.get(context.recent_empty)
    assert Process.alive?(pruner)
  end

  test "pruner accepts an additional tick and remains alive", _context do
    pruner = start_supervised!({RoomPruner, initial_delay_ms: to_timeout(hour: 1)})

    send(pruner, :prune)
    _state = :sys.get_state(pruner)
    send(pruner, :prune)
    _state = :sys.get_state(pruner)

    assert Process.alive?(pruner)
  end
end
