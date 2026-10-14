defmodule Analysis.PrivateRoomTest do
  use ExUnit.Case, async: false

  alias Analysis.{Analyses, AnalysisStore, Rooms, RoomStore, Users}
  alias OpenChessLab.Repo

  setup do
    {:ok, owner} = Users.create()
    {:ok, other} = Users.create()
    suffix = Base.encode16(:crypto.strong_rand_bytes(4))
    code = "PRV" <> suffix

    on_exit(fn ->
      RoomStore.delete(code)
      Users.delete(owner.id)
      Users.delete(other.id)
    end)

    %{owner: owner, other: other, code: code}
  end

  test "creating a private room makes the owner its first and only member", ctx do
    assert {:ok, room} = Rooms.create_room(ctx.code, owner: ctx.owner.id)
    assert room.owner_user_id == ctx.owner.id
    assert Rooms.member?(ctx.code, ctx.owner.id)
    refute Rooms.member?(ctx.code, ctx.other.id)
    refute Rooms.member?(ctx.code, nil)

    # Public rooms keep bearer-code semantics: no membership required.
    public = "PUB" <> Base.encode16(:crypto.strong_rand_bytes(4))
    assert {:ok, public_room} = Rooms.create_room(public)
    assert is_nil(public_room.owner_user_id)
    refute Rooms.member?(public, ctx.other.id)
    RoomStore.delete(public)
  end

  test "invite links admit members until revoked or rotated", ctx do
    assert {:ok, room} = Rooms.create_room(ctx.code, owner: ctx.owner.id)

    # No link yet: nobody joins, not even with a forged token.
    assert {:error, :invalid_invite} = Rooms.consume_invite(ctx.code, ctx.other.id, "forged")
    refute Rooms.member?(ctx.code, ctx.other.id)

    assert {:ok, token} = Rooms.create_invite(ctx.code)
    assert Rooms.invite_active?(ctx.code)

    # Multi-use: the same link admits a member, and rejoining is idempotent.
    assert {:ok, :joined} = Rooms.consume_invite(ctx.code, ctx.other.id, token)
    assert {:ok, :joined} = Rooms.consume_invite(ctx.code, ctx.other.id, token)
    assert Rooms.member?(ctx.code, ctx.other.id)

    # Only the SHA-256 hash of the token is stored, never the raw token.
    [[hash]] =
      Repo.query!("SELECT token_hash FROM room_invites WHERE room_id = $1", [ctx.code]).rows

    assert byte_size(hash) == 32
    refute hash == token

    # Revoke: new joins stop immediately; existing members keep access.
    assert Rooms.revoke_invites(ctx.code) == 1
    assert {:error, :invalid_invite} = Rooms.consume_invite(ctx.code, ctx.owner.id, token)
    assert Rooms.member?(ctx.code, ctx.other.id)

    # Rotation: generating a new link invalidates the old one.
    assert {:ok, token2} = Rooms.create_invite(ctx.code)
    assert {:error, :invalid_invite} = Rooms.consume_invite(ctx.code, ctx.owner.id, token)
    assert {:ok, :joined} = Rooms.consume_invite(ctx.code, ctx.owner.id, token2)

    assert room.owner_user_id == ctx.owner.id
  end

  test "concurrent consumption and revocation: cutoff wins", ctx do
    assert {:ok, _room} = Rooms.create_room(ctx.code, owner: ctx.owner.id)
    assert {:ok, token} = Rooms.create_invite(ctx.code)

    consumers =
      for _ <- 1..8,
          do: Task.async(fn -> Rooms.consume_invite(ctx.code, ctx.other.id, token) end)

    revoker = Task.async(fn -> Rooms.revoke_invites(ctx.code) end)
    Enum.map(consumers, &Task.await/1)
    Task.await(revoker)

    # Whatever interleaving happened, the token is dead after the revoke.
    assert {:error, :invalid_invite} = Rooms.consume_invite(ctx.code, ctx.owner.id, token)
    refute Rooms.invite_active?(ctx.code)
  end

  test "public rooms expose analyses without membership", ctx do
    public = "PUB2" <> Base.encode16(:crypto.strong_rand_bytes(4))
    assert {:ok, _} = Rooms.create_room(public)

    analysis_id = "prv-analysis-" <> Integer.to_string(System.unique_integer([:positive]))
    assert {:ok, _analysis, 1} = Analyses.create(analysis_id)
    :ok = Rooms.add_analysis(public, analysis_id)

    assert {:ok, room} = Rooms.get(public)
    assert is_nil(room.owner_user_id)
    assert room.analysis_ids == [analysis_id]

    RoomStore.delete(public)
    AnalysisStore.delete(analysis_id, 1)
    refute Rooms.member?(public, ctx.other.id)
    _ = ctx.code
  end
end
