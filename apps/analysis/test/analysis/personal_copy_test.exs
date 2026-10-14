defmodule Analysis.PersonalCopyTest do
  use ExUnit.Case, async: false

  alias Analysis.Analysis, as: AnalysisModel
  alias Analysis.AnalysisStore
  alias Analysis.GameStart
  alias Analysis.RoomStore
  alias Analysis.UserLibrary
  alias Analysis.Users
  alias OpenChessLab.Repo

  setup do
    {:ok, user} = Users.create()
    {:ok, other} = Users.create()
    id = "copy-source-" <> Ecto.UUID.generate()
    room = "copy-room-" <> Ecto.UUID.generate()

    source =
      AnalysisModel.new(id, 42, "source-record", GameStart.new(17), %{"Event" => "Test"})
      |> AnalysisModel.add_child([], {:move, Chess.Move.new(12, 28)}, 43)
      |> AnalysisModel.add_child([], :edit, 44)
      |> AnalysisModel.add_child([0], :edit, 45)

    {:ok, source} = AnalysisModel.set_comment(source, [0, 0], "A private continuation later")
    {:ok, source} = AnalysisModel.set_nags(source, [0], [1, 5])
    {:ok, 1} = AnalysisStore.insert(source)
    :ok = RoomStore.create(room)
    :ok = RoomStore.add_analysis(room, id)

    on_exit(fn ->
      for owner <- [user, other] do
        for copy <- UserLibrary.list(owner.id),
            do: Repo.query!("DELETE FROM analyses WHERE analysis_id = $1", [copy])

        Users.delete(owner.id)
      end

      RoomStore.delete(room)
      Repo.query!("DELETE FROM analyses WHERE analysis_id = $1", [id])
    end)

    %{user: user, other: other, source: source, room: room}
  end

  test "copies the whole aggregate and edits diverge in both directions", ctx do
    assert {:ok, id} = UserLibrary.copy_from_room(ctx.user.id, ctx.room, ctx.source.id)
    refute id == ctx.source.id
    assert {:ok, copy, 1} = AnalysisStore.get(id)
    assert %{copy | id: ctx.source.id} == ctx.source
    assert UserLibrary.list(ctx.user.id) == [id]
    assert UserLibrary.list(ctx.other.id) == []
    assert {:ok, room} = RoomStore.get(ctx.room)
    assert room.analysis_ids == [ctx.source.id]

    {:ok, changed_source} = AnalysisModel.set_comment(ctx.source, [], "Shared change")
    assert {:ok, 2} = AnalysisStore.update(changed_source, 1)
    assert {:ok, ^copy, 1} = AnalysisStore.get(id)
    {:ok, changed_copy} = AnalysisModel.set_comment(copy, [0], "Only in my copy")
    assert {:ok, 2} = AnalysisStore.update(changed_copy, 1)
    assert {:ok, ^changed_source, 2} = AnalysisStore.get(ctx.source.id)

    :ok = RoomStore.delete(ctx.room)
    :ok = AnalysisStore.delete(ctx.source.id, 2)
    assert {:ok, ^changed_copy, 2} = AnalysisStore.get(id)
  end

  test "repeated and concurrent saves create separate snapshots for each owner", ctx do
    owners = [ctx.user.id, ctx.other.id, ctx.user.id, ctx.other.id]

    results =
      owners
      |> Task.async_stream(&UserLibrary.copy_from_room(&1, ctx.room, ctx.source.id),
        max_concurrency: 4
      )
      |> Enum.map(fn {:ok, {:ok, id}} -> id end)

    assert length(Enum.uniq(results)) == 4

    assert Enum.sort(UserLibrary.list(ctx.user.id)) ==
             Enum.sort([Enum.at(results, 0), Enum.at(results, 2)])

    assert Enum.sort(UserLibrary.list(ctx.other.id)) ==
             Enum.sort([Enum.at(results, 1), Enum.at(results, 3)])
  end

  test "unknown users and analyses outside the durable room are rejected without writes", ctx do
    before = count_analyses()

    assert {:error, :invalid_identity} =
             UserLibrary.copy_from_room("invalid", ctx.room, ctx.source.id)

    assert {:error, :invalid_identity} = UserLibrary.copy_from_room(ctx.user.id, ctx.room, nil)

    assert {:error, :user_not_found} =
             UserLibrary.copy_from_room(Ecto.UUID.generate(), ctx.room, ctx.source.id)

    assert {:error, :analysis_not_found} =
             UserLibrary.copy_from_room(ctx.user.id, "absent-room", ctx.source.id)

    assert {:error, :analysis_not_found} =
             UserLibrary.copy_from_room(ctx.user.id, ctx.room, "absent-analysis")

    RoomStore.remove_analysis(ctx.room, ctx.source.id)

    assert {:error, :analysis_not_found} =
             UserLibrary.copy_from_room(ctx.user.id, ctx.room, ctx.source.id)

    assert count_analyses() == before
    assert UserLibrary.list(ctx.user.id) == []
  end

  test "a failed library insertion rolls back the newly inserted analysis", ctx do
    before = count_analyses()
    # A real PostgreSQL failure after the aggregate insert proves atomicity.
    Repo.query!(
      "ALTER TABLE user_analyses ADD CONSTRAINT reject_copy_fixture CHECK (user_id <> '#{ctx.user.id}'::uuid)",
      []
    )

    try do
      assert_raise Postgrex.Error, fn ->
        UserLibrary.copy_from_room(ctx.user.id, ctx.room, ctx.source.id)
      end
    after
      Repo.query!("ALTER TABLE user_analyses DROP CONSTRAINT reject_copy_fixture", [])
    end

    assert count_analyses() == before
    assert UserLibrary.list(ctx.user.id) == []
    assert {:ok, source, 1} = AnalysisStore.get(ctx.source.id)
    assert source == ctx.source
  end

  defp count_analyses, do: Repo.query!("SELECT count(*) FROM analyses", []).rows
end
