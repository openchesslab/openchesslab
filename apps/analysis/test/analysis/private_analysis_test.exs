defmodule Analysis.PrivateAnalysisTest do
  use ExUnit.Case, async: false

  alias Analysis.Analyses
  alias Analysis.AnalysisStore
  alias Analysis.RoomStore
  alias Analysis.UserLibrary
  alias Analysis.Users
  alias OpenChessLab.Repo

  setup do
    {:ok, user} = Users.create()
    {:ok, other} = Users.create()
    source = "private-source-" <> Ecto.UUID.generate()
    room = "private-room-" <> Ecto.UUID.generate()
    id = "private-copy-" <> Ecto.UUID.generate()
    {:ok, _, 1} = Analyses.create(source)
    :ok = RoomStore.create(room)
    :ok = RoomStore.add_analysis(room, source)
    # A materialized private copy: a standalone analysis this user owns,
    # not shared with any room (what branching a reference will produce).
    {:ok, _, 1} = Analyses.create(id)
    :ok = UserLibrary.save(user.id, id)

    on_exit(fn ->
      RoomStore.delete(room)

      for analysis_id <- [source, id],
          do: Repo.query!("DELETE FROM analyses WHERE analysis_id = $1", [analysis_id])

      Users.delete(user.id)
      Users.delete(other.id)
    end)

    %{user: user, other: other, source: source, room: room, id: id}
  end

  test "only the personal copy is accessible, never guessed IDs or room references", ctx do
    assert {:ok, _, 1} = UserLibrary.get_private(ctx.user.id, ctx.id)

    for {owner, id} <- [
          {ctx.other.id, ctx.id},
          {ctx.user.id, ctx.source},
          {"invalid", ctx.id},
          {ctx.user.id, "missing"}
        ] do
      assert :not_found = UserLibrary.get_private(owner, id)

      assert {:error, :analysis_not_found} =
               UserLibrary.edit_private(owner, id, 1, [], {:comment, "forged"})
    end

    :ok = UserLibrary.save(ctx.user.id, ctx.source)
    assert :not_found = UserLibrary.get_private(ctx.user.id, ctx.source)
  end

  test "opening a live reference branches a private copy once and repoints the entry", ctx do
    assert {:ok, :tracked} = UserLibrary.track_from_room(ctx.user.id, ctx.room, ctx.source)

    assert {:ok, copy_id} = UserLibrary.open_private(ctx.user.id, ctx.source)
    refute copy_id == ctx.source
    assert UserLibrary.list(ctx.user.id) == [ctx.id, copy_id]

    # The copy preserves the aggregate; the room's original is untouched.
    assert {:ok, copy, 1} = AnalysisStore.get(copy_id)
    assert {:ok, source, 1} = AnalysisStore.get(ctx.source)
    assert %{copy | id: ctx.source} == source
    assert {:ok, room} = RoomStore.get(ctx.room)
    assert ctx.source in room.analysis_ids

    # Branching is idempotent: the entry now opens as itself.
    assert {:ok, ^copy_id} = UserLibrary.open_private(ctx.user.id, copy_id)

    # Another user's reference keeps the original; theirs branches separately.
    assert {:ok, :tracked} = UserLibrary.track_from_room(ctx.other.id, ctx.room, ctx.source)
    assert UserLibrary.list(ctx.other.id) == [ctx.source]

    assert {:ok, other_copy} = UserLibrary.open_private(ctx.other.id, ctx.source)
    refute other_copy in [ctx.source, copy_id]
    assert UserLibrary.list(ctx.other.id) == [other_copy]

    assert {:error, :analysis_not_found} = UserLibrary.open_private(ctx.user.id, "missing")
    assert {:error, :invalid_identity} = UserLibrary.open_private("invalid", ctx.source)
  end

  test "an already-private entry opens unchanged without copying", ctx do
    assert {:ok, id} = UserLibrary.open_private(ctx.user.id, ctx.id)
    assert id == ctx.id
    assert UserLibrary.list(ctx.user.id) == [ctx.id]

    # An entry only referenced by another user (no room) branches as well.
    :ok = UserLibrary.save(ctx.other.id, ctx.id)
    assert {:ok, copy_id} = UserLibrary.open_private(ctx.user.id, ctx.id)
    refute copy_id == ctx.id
    assert UserLibrary.list(ctx.user.id) == [copy_id]
    assert UserLibrary.list(ctx.other.id) == [ctx.id]
  end

  test "moves, comments, annotations and variants persist without changing the room", ctx do
    assert {:ok, _, 2, [0]} = edit(ctx, 1, [], {:play, Chess.Move.new(12, 28)})
    assert {:ok, _, 3, [1]} = edit(ctx, 2, [], {:play, Chess.Move.new(11, 27)})
    assert {:ok, _, 4} = edit(ctx, 3, [1], {:comment, "Private"})
    assert {:ok, _, 5} = edit(ctx, 4, [1], {:nags, [1]})
    assert {:ok, copy, 6, [0]} = edit(ctx, 5, [1], :promote)
    assert Analysis.Node.comment(Analysis.Analysis.node_at(copy, [0])) == "Private"
    assert {:ok, _, 7, []} = edit(ctx, 6, [1], :remove)
    assert {:ok, source, 1} = AnalysisStore.get(ctx.source)
    assert source.root.children == []
    assert {:ok, room} = RoomStore.get(ctx.room)
    assert room.analysis_ids == [ctx.source]

    assert Repo.query!("SELECT room_id FROM room_analyses WHERE analysis_id = $1", [ctx.id]).rows ==
             []
  end

  test "removal and shared references revoke private reads and writes", ctx do
    :ok = UserLibrary.save(ctx.other.id, ctx.id)
    assert :not_found = UserLibrary.get_private(ctx.user.id, ctx.id)
    assert {:error, :analysis_not_found} = edit(ctx, 1, [], {:comment, "Denied"})
    :ok = UserLibrary.remove(ctx.other.id, ctx.id)
    :ok = RoomStore.add_analysis(ctx.room, ctx.id)
    assert :not_found = UserLibrary.get_private(ctx.user.id, ctx.id)
    :ok = RoomStore.remove_analysis(ctx.room, ctx.id)
    :ok = UserLibrary.remove(ctx.user.id, ctx.id)
    assert :not_found = UserLibrary.get_private(ctx.user.id, ctx.id)
    assert {:error, :analysis_not_found} = edit(ctx, 1, [], {:comment, "Denied"})
    assert {:ok, _, 1} = AnalysisStore.get(ctx.id)
  end

  test "concurrent tabs cannot overwrite a displayed revision", ctx do
    results =
      ["First", "Second"]
      |> Task.async_stream(&edit(ctx, 1, [], {:comment, &1}), max_concurrency: 2)
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, _, 2}, &1)) == 1
    assert {:error, :conflict} in results
    assert {:ok, _, 2} = UserLibrary.get_private(ctx.user.id, ctx.id)
  end

  test "failed edits leave the revision and aggregate intact", ctx do
    assert {:error, :illegal_move} = edit(ctx, 1, [], {:play, Chess.Move.new(12, 36)})
    assert {:error, :node_not_found} = edit(ctx, 1, [90], {:comment, "Bad path"})
    assert {:error, :invalid_nags} = edit(ctx, 1, [], {:nags, [999]})
    assert {:ok, _, 1} = UserLibrary.get_private(ctx.user.id, ctx.id)
  end

  defp edit(ctx, revision, path, command),
    do: UserLibrary.edit_private(ctx.user.id, ctx.id, revision, path, command)
end
