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

  test "the member list shows names and removal respects the owner's authority", ctx do
    assert {:ok, room} =
             Rooms.create_room(ctx.code,
               owner: ctx.owner.id,
               owner_display_name: "Wise Otter 42"
             )

    {:ok, token} = Rooms.create_invite(ctx.code)
    assert {:ok, :joined} = Rooms.consume_invite(ctx.code, ctx.other.id, token, "Keen Rhino 44")

    # The list is oldest-join first with the owner at the top.
    [owner_member, joined_member] = Rooms.members(ctx.code)
    assert owner_member.display_name == "Wise Otter 42"
    assert joined_member.display_name == "Keen Rhino 44"

    # Only the owner may remove; their own membership is immutable.
    assert {:error, :not_owner} = Rooms.remove_member(ctx.code, ctx.other.id, ctx.other.id)
    assert {:error, :owner_immutable} = Rooms.remove_member(ctx.code, ctx.owner.id, ctx.owner.id)

    # Removal takes effect and cannot be repeated; the removed user may still
    # rejoin through an active invite link.
    assert :ok = Rooms.remove_member(ctx.code, ctx.owner.id, ctx.other.id)
    refute Rooms.member?(ctx.code, ctx.other.id)
    assert {:error, :member_not_found} = Rooms.remove_member(ctx.code, ctx.owner.id, ctx.other.id)
    assert {:ok, :joined} = Rooms.consume_invite(ctx.code, ctx.other.id, token, "Keen Rhino 45")
    assert Rooms.member?(ctx.code, ctx.other.id)

    assert room.owner_user_id == ctx.owner.id
  end

  test "creating a private room makes the owner its first and only member", ctx do
    assert {:ok, room} =
             Rooms.create_room(ctx.code, owner: ctx.owner.id, owner_display_name: "Wise Otter 42")

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
    assert {:ok, room} =
             Rooms.create_room(ctx.code, owner: ctx.owner.id, owner_display_name: "Wise Otter 42")

    # No link yet: nobody joins, not even with a forged token.
    assert {:error, :invalid_invite} =
             Rooms.consume_invite(ctx.code, ctx.other.id, "forged", "Keen Rhino 44")

    refute Rooms.member?(ctx.code, ctx.other.id)

    assert {:ok, token} = Rooms.create_invite(ctx.code)
    assert Rooms.invite_active?(ctx.code)

    # Multi-use: the same link admits a member, and rejoining is idempotent.
    assert {:ok, :joined} = Rooms.consume_invite(ctx.code, ctx.other.id, token, "Keen Rhino 44")
    assert {:ok, :joined} = Rooms.consume_invite(ctx.code, ctx.other.id, token, "Keen Rhino 44")
    assert Rooms.member?(ctx.code, ctx.other.id)

    # Only the SHA-256 hash of the token is stored, never the raw token.
    [[hash]] =
      Repo.query!("SELECT token_hash FROM room_invites WHERE room_id = $1", [ctx.code]).rows

    assert byte_size(hash) == 32
    refute hash == token

    # Revoke: new joins stop immediately; existing members keep access.
    assert Rooms.revoke_invites(ctx.code) == 1

    assert {:error, :invalid_invite} =
             Rooms.consume_invite(ctx.code, ctx.owner.id, token, "Wise Otter 43")

    assert Rooms.member?(ctx.code, ctx.other.id)

    # Rotation: generating a new link invalidates the old one.
    assert {:ok, token2} = Rooms.create_invite(ctx.code)

    assert {:error, :invalid_invite} =
             Rooms.consume_invite(ctx.code, ctx.owner.id, token, "Wise Otter 43")

    assert {:ok, :joined} = Rooms.consume_invite(ctx.code, ctx.owner.id, token2, "Wise Otter 43")

    assert room.owner_user_id == ctx.owner.id
  end

  test "concurrent consumption and revocation: cutoff wins", ctx do
    assert {:ok, _room} =
             Rooms.create_room(ctx.code, owner: ctx.owner.id, owner_display_name: "Wise Otter 42")

    assert {:ok, token} = Rooms.create_invite(ctx.code)

    consumers =
      for _ <- 1..8,
          do:
            Task.async(fn ->
              Rooms.consume_invite(ctx.code, ctx.other.id, token, "Keen Rhino 44")
            end)

    revoker = Task.async(fn -> Rooms.revoke_invites(ctx.code) end)
    Enum.map(consumers, &Task.await/1)
    Task.await(revoker)

    # Whatever interleaving happened, the token is dead after the revoke.
    assert {:error, :invalid_invite} =
             Rooms.consume_invite(ctx.code, ctx.owner.id, token, "Wise Otter 43")

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
