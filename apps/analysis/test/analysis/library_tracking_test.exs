defmodule Analysis.LibraryTrackingTest do
  use ExUnit.Case, async: false

  alias Analysis.Analyses
  alias Analysis.Analysis, as: AnalysisModel
  alias Analysis.AnalysisStore
  alias Analysis.RoomStore
  alias Analysis.UserLibrary
  alias Analysis.Users
  alias OpenChessLab.Repo

  setup do
    {:ok, user} = Users.create()
    {:ok, other} = Users.create()
    id = "track-source-" <> Ecto.UUID.generate()
    room = "track-room-" <> Ecto.UUID.generate()
    {:ok, _, 1} = Analyses.create(id)
    :ok = RoomStore.create(room)
    :ok = RoomStore.add_analysis(room, id)

    on_exit(fn ->
      RoomStore.delete(room)
      Repo.query!("DELETE FROM analyses WHERE analysis_id = $1", [id])
      Users.delete(user.id)
      Users.delete(other.id)
    end)

    %{user: user, other: other, id: id, room: room}
  end

  test "tracking references the room's own analysis and follows its work", ctx do
    assert {:ok, :tracked} = UserLibrary.track_from_room(ctx.user.id, ctx.room, ctx.id)
    assert UserLibrary.list(ctx.user.id) == [ctx.id]
    assert UserLibrary.list(ctx.other.id) == []
    assert {:ok, room} = RoomStore.get(ctx.room)
    assert room.analysis_ids == [ctx.id]

    # No copy exists: the library entry is the room's analysis itself, so
    # later room work is reflected through the same id and revision.
    assert {:ok, analysis, 1} = AnalysisStore.get(ctx.id)
    {:ok, changed} = AnalysisModel.set_comment(analysis, [], "Shared room work")
    assert {:ok, 2} = AnalysisStore.update(changed, 1)
    assert UserLibrary.list(ctx.user.id) == [ctx.id]
    assert {:ok, _, 2} = AnalysisStore.get(ctx.id)

    assert {:ok, :already_tracked} = UserLibrary.track_from_room(ctx.user.id, ctx.room, ctx.id)
    assert UserLibrary.list(ctx.user.id) == [ctx.id]

    # Untracking removes only the reference, never the analysis or room content.
    assert :ok = UserLibrary.remove(ctx.user.id, ctx.id)
    assert UserLibrary.list(ctx.user.id) == []
    assert {:ok, _, 2} = AnalysisStore.get(ctx.id)
    assert {:ok, room} = RoomStore.get(ctx.room)
    assert room.analysis_ids == [ctx.id]
  end

  test "repeated and concurrent tracking converges on one reference per owner", ctx do
    owners = [ctx.user.id, ctx.other.id, ctx.user.id, ctx.other.id]

    results =
      owners
      |> Task.async_stream(&UserLibrary.track_from_room(&1, ctx.room, ctx.id), max_concurrency: 4)
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.all?(results, &match?({:ok, _}, &1))
    assert UserLibrary.list(ctx.user.id) == [ctx.id]
    assert UserLibrary.list(ctx.other.id) == [ctx.id]

    assert [[1]] ==
             Repo.query!("SELECT count(*) FROM analyses WHERE analysis_id = $1", [ctx.id]).rows
  end

  test "tracked/2 returns the referenced subset for the requesting user", ctx do
    assert UserLibrary.tracked(ctx.user.id, [ctx.id, "other-analysis"]) == []
    assert {:ok, :tracked} = UserLibrary.track_from_room(ctx.user.id, ctx.room, ctx.id)
    assert UserLibrary.tracked(ctx.user.id, [ctx.id, "other-analysis"]) == [ctx.id]
    assert UserLibrary.tracked(ctx.other.id, [ctx.id]) == []
    assert UserLibrary.tracked("invalid", [ctx.id]) == []
    assert UserLibrary.tracked(ctx.user.id, []) == []
  end

  test "unknown users and analyses outside the durable room are rejected without writes", ctx do
    before = count_analyses()

    assert {:error, :invalid_identity} =
             UserLibrary.track_from_room("invalid", ctx.room, ctx.id)

    assert {:error, :invalid_identity} = UserLibrary.track_from_room(ctx.user.id, ctx.room, nil)

    assert {:error, :user_not_found} =
             UserLibrary.track_from_room(Ecto.UUID.generate(), ctx.room, ctx.id)

    assert {:error, :analysis_not_found} =
             UserLibrary.track_from_room(ctx.user.id, "absent-room", ctx.id)

    assert {:error, :analysis_not_found} =
             UserLibrary.track_from_room(ctx.user.id, ctx.room, "absent-analysis")

    RoomStore.remove_analysis(ctx.room, ctx.id)

    assert {:error, :analysis_not_found} =
             UserLibrary.track_from_room(ctx.user.id, ctx.room, ctx.id)

    assert count_analyses() == before
    assert UserLibrary.list(ctx.user.id) == []
  end

  test "a failed reference insertion leaves no trace", ctx do
    before = count_analyses()

    Repo.query!(
      "ALTER TABLE user_analyses ADD CONSTRAINT reject_track_fixture CHECK (user_id <> '#{ctx.user.id}'::uuid)",
      []
    )

    try do
      assert_raise Postgrex.Error, fn ->
        UserLibrary.track_from_room(ctx.user.id, ctx.room, ctx.id)
      end
    after
      Repo.query!("ALTER TABLE user_analyses DROP CONSTRAINT reject_track_fixture", [])
    end

    assert count_analyses() == before
    assert UserLibrary.list(ctx.user.id) == []
  end

  defp count_analyses do
    [[count]] = Repo.query!("SELECT count(*) FROM analyses", []).rows
    count
  end
end
