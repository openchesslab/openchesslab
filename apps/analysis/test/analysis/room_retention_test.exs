defmodule Analysis.RoomRetentionTest do
  use ExUnit.Case, async: false

  alias Analysis.{Analyses, Rooms, RoomStore, UserLibrary, Users}
  alias OpenChessLab.Repo

  defp backdate(room_id, days) do
    Repo.query!(
      "UPDATE rooms SET last_active_at = now() - make_interval(days => $2) WHERE id = $1",
      [room_id, days]
    )
  end

  test "an inactive populated room is pruned with its analyses; active rooms survive" do
    suffix = Base.encode16(:crypto.strong_rand_bytes(4))

    {:ok, _} = Rooms.start_room("RR-OLD-" <> suffix)
    {:ok, _} = Rooms.start_room("RR-ACTIVE-" <> suffix)
    {:ok, analysis, _} = Analyses.create("analysis-rr-" <> suffix)
    :ok = Rooms.add_analysis("RR-OLD-" <> suffix, analysis.id)

    backdate("RR-OLD-" <> suffix, 4)
    backdate("RR-ACTIVE-" <> suffix, 1)

    assert ["RR-OLD-" <> suffix] = Rooms.prune_inactive_rooms(3, 100)

    assert :not_found = RoomStore.get("RR-OLD-" <> suffix)
    assert {:ok, _} = RoomStore.get("RR-ACTIVE-" <> suffix)

    # The room's analysis aggregate is gone; the room row is gone with its
    # memberships/links (FK cascade).
    assert :not_found = Analyses.get(analysis.id)
  end

  test "a library reference is materialized before its room is pruned" do
    suffix = Base.encode16(:crypto.strong_rand_bytes(4))
    {:ok, user} = Users.create()
    on_exit(fn -> Users.delete(user.id) end)

    {:ok, _} = Rooms.start_room("RR-LIB-" <> suffix)
    {:ok, analysis, _} = Analyses.create("analysis-rrl-" <> suffix)
    :ok = Rooms.add_analysis("RR-LIB-" <> suffix, analysis.id)

    assert {:ok, :tracked} =
             UserLibrary.track_from_room(user.id, "RR-LIB-" <> suffix, analysis.id)

    {:ok, original, _} = Analyses.get(analysis.id)
    backdate("RR-LIB-" <> suffix, 4)

    assert ["RR-LIB-" <> suffix] = Rooms.prune_inactive_rooms(3, 100)

    # The library entry now points at an independent copy with equal content.
    page = UserLibrary.page(user.id)
    assert [%{id: new_id}] = page.entries
    refute new_id == analysis.id
    assert {:ok, copy, _} = Analyses.get(new_id)

    # The copy has the same tree content as the original had.
    assert copy == %{original | id: copy.id}
  end

  defp record_of(analysis_id) do
    case Repo.query!("SELECT record FROM analyses WHERE analysis_id = $1", [analysis_id]).rows do
      [[record]] -> {:ok, record}
      [] -> :not_found
    end
  end

  test "visits and chat count as activity", %{} do
    suffix = Base.encode16(:crypto.strong_rand_bytes(4))
    code = "RR-TOUCH-" <> suffix
    {:ok, _} = Rooms.start_room(code)

    backdate(code, 2)
    assert :ok = Rooms.touch(code)

    [[fresh]] =
      Repo.query!("SELECT last_active_at > now() - interval '1 hour' FROM rooms WHERE id = $1", [
        code
      ]).rows

    assert fresh
  end
end
