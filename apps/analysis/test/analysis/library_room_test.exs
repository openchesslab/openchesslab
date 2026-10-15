defmodule Analysis.LibraryRoomTest do
  use ExUnit.Case, async: false

  alias Analysis.{Analyses, AnalysisStore, RoomStore, UserLibrary, Users}
  alias OpenChessLab.Repo

  setup do
    {:ok, user} = Users.create()
    {:ok, other} = Users.create()
    id = "library-room-" <> Ecto.UUID.generate()
    {:ok, _, 1} = Analyses.create(id)
    :ok = UserLibrary.save(user.id, id)

    on_exit(fn ->
      for owner <- [user, other] do
        Repo.query!("DELETE FROM rooms WHERE owner_user_id = $1", [Ecto.UUID.dump!(owner.id)])

        for entry <- UserLibrary.list(owner.id),
            do: Repo.query!("DELETE FROM analyses WHERE analysis_id = $1", [entry])

        Users.delete(owner.id)
      end

      Repo.query!("DELETE FROM analyses WHERE analysis_id = $1", [id])
    end)

    %{user: user, other: other, id: id, code: "LR" <> Ecto.UUID.generate()}
  end

  test "standalone entry opens unchanged and subsequent/concurrent opens reuse the room", ctx do
    results =
      1..4
      |> Task.async_stream(fn n ->
        UserLibrary.open_room(ctx.user.id, ctx.id, ctx.code <> "#{n}", "Quiet Fox")
      end)
      |> Enum.map(fn {:ok, result} -> result end)

    assert [{:ok, result}] = Enum.uniq(results)
    assert result.analysis_id == ctx.id
    assert {:ok, room} = RoomStore.get(result.room_id)
    assert room.owner_user_id == ctx.user.id
    assert room.analysis_ids == [ctx.id]
    assert RoomStore.member?(room.id, ctx.user.id)
    refute RoomStore.member?(room.id, ctx.other.id)
    assert {:ok, ^result} = UserLibrary.open_room(ctx.user.id, ctx.id, ctx.code, "Quiet Fox")
  end

  test "shared entry branches atomically, keeps its title and leaves other references intact",
       ctx do
    :ok = UserLibrary.save(ctx.other.id, ctx.id)
    :ok = UserLibrary.rename(ctx.user.id, ctx.id, "My study")
    {:ok, _, 2} = Analyses.set_comment(ctx.id, [], "Original")
    assert {:ok, result} = UserLibrary.open_room(ctx.user.id, ctx.id, ctx.code, "Quiet Fox")
    refute result.analysis_id == ctx.id
    assert UserLibrary.list(ctx.user.id) == [result.analysis_id]
    assert UserLibrary.list(ctx.other.id) == [ctx.id]
    assert {:ok, "My study"} = UserLibrary.title(ctx.user.id, result.analysis_id)
    assert {:ok, copy, 1} = AnalysisStore.get(result.analysis_id)
    assert {:ok, original, 2} = AnalysisStore.get(ctx.id)
    assert %{copy | id: ctx.id} == original
    assert {:ok, _, 2} = Analyses.set_comment(result.analysis_id, [], "Independent")
    assert {:ok, ^original, 2} = AnalysisStore.get(ctx.id)
  end

  test "foreign, removed and malformed entries create no room", ctx do
    assert {:error, :analysis_not_found} =
             UserLibrary.open_room(ctx.other.id, ctx.id, ctx.code, "Fox")

    UserLibrary.remove(ctx.user.id, ctx.id)

    assert {:error, :analysis_not_found} =
             UserLibrary.open_room(ctx.user.id, ctx.id, ctx.code, "Fox")

    assert {:error, :invalid_identity} = UserLibrary.open_room("invalid", ctx.id, ctx.code, "Fox")
    assert :not_found = RoomStore.get(ctx.code)
  end

  test "a code collision rolls back copy and reference changes", ctx do
    :ok = UserLibrary.save(ctx.other.id, ctx.id)
    :ok = RoomStore.create_private(ctx.code, ctx.other.id, "Other Fox")
    before = Repo.query!("SELECT count(*) FROM analyses", []).rows
    assert {:error, :already_exists} = UserLibrary.open_room(ctx.user.id, ctx.id, ctx.code, "Fox")
    assert UserLibrary.list(ctx.user.id) == [ctx.id]
    assert Repo.query!("SELECT count(*) FROM analyses", []).rows == before
    assert {:ok, room} = RoomStore.get(ctx.code)
    assert room.analysis_ids == []
  end
end
