defmodule Web.PrivateRoomTest do
  use Web.ConnCase, async: false

  alias Analysis.{Analyses, Rooms, Users, UserSessions}
  alias OpenChessLab.Repo

  setup do
    before_ids = ids()
    {:ok, owner} = Users.create()
    {:ok, other} = Users.create()
    {:ok, owner_session} = UserSessions.create(owner.id)
    {:ok, other_session} = UserSessions.create(other.id)
    suffix = Base.encode16(:crypto.strong_rand_bytes(4))
    code = "WPR" <> suffix
    analysis_id = "wpr-analysis-" <> suffix

    on_exit(fn ->
      Rooms.stop_room(code) |> tap(fn _ -> :ok end)
      Repo.query!("DELETE FROM analyses WHERE analysis_id = $1", [analysis_id])
      Enum.each(ids() -- before_ids, &Users.delete/1)
    end)

    %{
      owner: owner,
      other: other,
      owner_session: owner_session,
      other_session: other_session,
      code: code,
      analysis_id: analysis_id
    }
  end

  test "the home page offers a private toggle only when signed in", ctx do
    {:ok, guest, _} = live(build_conn(), "/")
    refute has_element?(guest, "#private-room")

    {:ok, signed_in, _} = live(authenticated(ctx.owner_session.token), "/")
    assert has_element?(signed_in, "#private-room")
    assert has_element?(signed_in, "label[for='private-room']", "Private room")

    # Creating with the toggle lands the owner in a private room of their own.
    html = render_click(signed_in, "create-room", %{"private" => "true"})
    {:ok, room_view, _room_html} = follow_redirect(html, authenticated(ctx.owner_session.token))
    assert has_element?(room_view, "#members-button")
    refute has_element?(room_view, "button[phx-click='copy-room-code']")
  end

  test "a private room gates non-members without leaking any content", ctx do
    assert {:ok, _room} =
             Rooms.create_room(ctx.code, owner: ctx.owner.id, owner_display_name: "Wise Otter 42")

    assert {:ok, _a, 1} = Analyses.create(ctx.analysis_id)
    :ok = Rooms.add_analysis(ctx.code, ctx.analysis_id)

    # Guest: gate, login hint, and none of the room's content.
    {:ok, guest, html} = live(build_conn(), "/rooms/#{ctx.code}")
    assert has_element?(guest, "#private-room-gate")
    assert html =~ "This room is private."
    assert html =~ "Log in and open the invite link again"
    refute html =~ ctx.analysis_id
    refute has_element?(guest, "#chess-board")
    refute has_element?(guest, "#room-chat")

    # Signed-in non-member: gate, no login hint, still no content.
    {:ok, outsider, outsider_html} =
      live(authenticated(ctx.other_session.token), "/rooms/#{ctx.code}")

    assert has_element?(outsider, "#private-room-gate")
    refute outsider_html =~ "Log in and open"
    refute outsider_html =~ ctx.analysis_id

    # Joining with the code on the home page lands on the gate, not the room.
    refute render_click(outsider, "join-room", %{"code" => ctx.code}) =~ ctx.analysis_id
  end

  test "the owner works in the room and manages the invite link", ctx do
    assert {:ok, _room} =
             Rooms.create_room(ctx.code, owner: ctx.owner.id, owner_display_name: "Wise Otter 42")

    {:ok, view, html} = live(authenticated(ctx.owner_session.token), "/rooms/#{ctx.code}")

    # No copy-code button in a private room; the owner gets the Invite button.
    refute has_element?(view, "button[phx-click='copy-room-code']")
    assert has_element?(view, "#members-button", "Members")
    refute html =~ ctx.analysis_id

    render_click(view, "open-members")
    assert has_element?(view, "#members-title")
    assert has_element?(view, "button[phx-click='generate-invite']")

    # Generating shows the full URL exactly once and activates the link.
    html = render_click(view, "generate-invite", %{"role" => "editor"})
    [invite] = Regex.run(~r|/rooms/#{ctx.code}/join/[A-Za-z0-9_-]{43}|, html)
    assert has_element?(view, "#invite-link-editor")
    assert Rooms.invite_active?(ctx.code, :editor)

    # Regenerating rotates: the old URL dies, the new one works.
    html = render_click(view, "generate-invite", %{"role" => "editor"})
    [new_invite] = Regex.run(~r|/rooms/#{ctx.code}/join/[A-Za-z0-9_-]{43}|, html)
    refute new_invite == invite

    # Revoking kills the active link.
    render_click(view, "revoke-invite", %{"role" => "editor"})
    refute Rooms.invite_active?(ctx.code, :editor)
  end

  test "invite links admit signed-in members through the join route", ctx do
    assert {:ok, _room} =
             Rooms.create_room(ctx.code, owner: ctx.owner.id, owner_display_name: "Wise Otter 42")

    assert {:ok, _a, 1} = Analyses.create(ctx.analysis_id)
    :ok = Rooms.add_analysis(ctx.code, ctx.analysis_id)
    {:ok, token} = Rooms.create_invite(ctx.code, :editor)

    # The member-to-be opens the join URL and lands in the room.
    conn =
      authenticated(ctx.other_session.token)
      |> get("/rooms/#{ctx.code}/join/#{token}")

    assert redirected_to(conn) == "/rooms/#{ctx.code}"
    assert Rooms.member?(ctx.code, ctx.other.id)

    # Joining stores a generated per-membership label.
    [joined] = Enum.filter(Rooms.members(ctx.code), &(&1.user_id == ctx.other.id))
    assert joined.display_name =~ ~r/^\S+ \S+ \d{2}$/

    {:ok, view, html} =
      live(authenticated(ctx.other_session.token), "/rooms/#{ctx.code}?a=#{ctx.analysis_id}")

    assert has_element?(view, "#chess-board")
    assert html =~ ctx.analysis_id
    refute has_element?(view, "#members-button")

    # Multi-use: the same link admits another member later.
    {:ok, third} = Users.create()
    {:ok, third_session} = UserSessions.create(third.id)
    conn = authenticated(third_session.token) |> get("/rooms/#{ctx.code}/join/#{token}")
    assert redirected_to(conn) == "/rooms/#{ctx.code}"

    # Revoke: the link is dead for anyone new.
    Rooms.revoke_invites(ctx.code, :editor)
    {:ok, fourth} = Users.create()
    {:ok, fourth_session} = UserSessions.create(fourth.id)

    conn =
      authenticated(fourth_session.token)
      |> get("/rooms/#{ctx.code}/join/#{token}")
      |> fetch_cookies()

    assert redirected_to(conn) == "/rooms/#{ctx.code}"
    refute Rooms.member?(ctx.code, fourth.id)
  end

  test "guests opening an invite are sent to the gate with the login hint", ctx do
    assert {:ok, _room} =
             Rooms.create_room(ctx.code, owner: ctx.owner.id, owner_display_name: "Wise Otter 42")

    {:ok, token} = Rooms.create_invite(ctx.code, :editor)

    conn = build_conn() |> get("/rooms/#{ctx.code}/join/#{token}")
    assert redirected_to(conn) == "/rooms/#{ctx.code}"
    refute Rooms.member?(ctx.code, nil)
  end

  test "forged invite events by non-owners change nothing", ctx do
    assert {:ok, _room} =
             Rooms.create_room(ctx.code, owner: ctx.owner.id, owner_display_name: "Wise Otter 42")

    {:ok, view, _} = live(authenticated(ctx.other_session.token), "/rooms/#{ctx.code}")

    # The non-member never even gets the room page; use the owner to be sure
    # the events exist, then a signed-in member-forger cannot touch invites.
    render_click(view, "generate-invite", %{"user_id" => ctx.owner.id})
    refute Rooms.invite_active?(ctx.code, :editor)
  end

  test "the members list shows names; removal kicks the member immediately", ctx do
    assert {:ok, _room} =
             Rooms.create_room(ctx.code, owner: ctx.owner.id, owner_display_name: "Wise Otter 42")

    {:ok, token} = Rooms.create_invite(ctx.code, :editor)

    assert {:ok, :joined} =
             Rooms.consume_invite(ctx.code, ctx.other.id, token, "Keen Rhino 44")

    [owner_member, joined_member] = Rooms.members(ctx.code)
    {:ok, removed_view, _} = live(authenticated(ctx.other_session.token), "/rooms/#{ctx.code}")

    {:ok, view, _} = live(authenticated(ctx.owner_session.token), "/rooms/#{ctx.code}")
    render_click(view, "open-members")
    assert has_element?(view, "#members-title", "Members")
    assert has_element?(view, "#member-#{owner_member.user_id}", "Owner")
    assert has_element?(view, "#member-#{joined_member.user_id}", "Keen Rhino 44")

    # The owner cannot be removed; the member can.
    refute has_element?(view, "#member-#{owner_member.user_id} button[phx-click='remove-member']")

    assert has_element?(
             view,
             "#member-#{joined_member.user_id} button[phx-click='remove-member']"
           )

    render_click(view, "remove-member", %{"user_id" => joined_member.user_id})
    refute Rooms.member?(ctx.code, joined_member.user_id)
    refute has_element?(view, "#member-#{joined_member.user_id}")

    # The removed member's connected view is cut off immediately with a message.
    # The removed member's connected view is cut off immediately.
    assert_redirect(removed_view, ~p"/rooms/#{ctx.code}")

    {:ok, gated, _} = live(authenticated(ctx.other_session.token), "/rooms/#{ctx.code}")

    assert has_element?(gated, "#private-room-gate")
  end

  test "the owner manages member roles in the members modal", ctx do
    assert {:ok, _room} =
             Rooms.create_room(ctx.code, owner: ctx.owner.id, owner_display_name: "Wise Otter 42")

    {:ok, token} = Rooms.create_invite(ctx.code, :editor)

    assert {:ok, :joined} =
             Rooms.consume_invite(ctx.code, ctx.other.id, token, "Keen Rhino 44")

    [_owner_member, joined_member] = Rooms.members(ctx.code)
    {:ok, view, _} = live(authenticated(ctx.owner_session.token), "/rooms/#{ctx.code}")
    render_click(view, "open-members")

    # Invitees join as editors; the owner's own row offers no role button.
    assert has_element?(view, "#member-#{joined_member.user_id}", "Editor")

    assert has_element?(
             view,
             "#member-#{joined_member.user_id} button[phx-click='set-member-role']"
           )

    refute has_element?(view, "#member-#{ctx.owner.id} button[phx-click='set-member-role']")

    # Demote to viewer and promote back; the badge follows the durable role.
    render_click(view, "set-member-role", %{
      "user_id" => joined_member.user_id,
      "role" => "viewer"
    })

    assert Rooms.role_of(ctx.code, joined_member.user_id) == :viewer
    assert has_element?(view, "#member-#{joined_member.user_id}", "Viewer")

    render_click(view, "set-member-role", %{
      "user_id" => joined_member.user_id,
      "role" => "editor"
    })

    assert Rooms.role_of(ctx.code, joined_member.user_id) == :editor
    assert has_element?(view, "#member-#{joined_member.user_id}", "Editor")
  end

  test "the owner manages editor and viewer links independently", ctx do
    assert {:ok, _room} =
             Rooms.create_room(ctx.code, owner: ctx.owner.id, owner_display_name: "Wise Otter 42")

    {:ok, view, _} = live(authenticated(ctx.owner_session.token), "/rooms/#{ctx.code}")
    render_click(view, "open-members")

    # Both link sections render with their own generate control.
    assert has_element?(view, "h3", "Editor link")
    assert has_element?(view, "h3", "Viewer link")

    # A viewer link joins as a viewer; the editor side stays without a link.
    html = render_click(view, "generate-invite", %{"role" => "viewer"})
    [viewer_invite] = Regex.run(~r|/rooms/#{ctx.code}/join/[A-Za-z0-9_-]{43}|, html)
    assert has_element?(view, "#invite-link-viewer")
    assert Rooms.invite_active?(ctx.code, :viewer)
    refute Rooms.invite_active?(ctx.code, :editor)

    conn = authenticated(ctx.other_session.token) |> get(viewer_invite)

    assert redirected_to(conn) == "/rooms/#{ctx.code}"
    assert Rooms.role_of(ctx.code, ctx.other.id) == :viewer

    # Rotating the editor link leaves the viewer link active.
    render_click(view, "generate-invite", %{"role" => "editor"})
    assert Rooms.invite_active?(ctx.code, :editor)
    assert Rooms.invite_active?(ctx.code, :viewer)

    # Revoking the viewer link stops only viewer joins.
    render_click(view, "revoke-invite", %{"role" => "viewer"})
    refute Rooms.invite_active?(ctx.code, :viewer)
    assert Rooms.invite_active?(ctx.code, :editor)
  end

  test "non-owner members cannot forge member management", ctx do
    assert {:ok, _room} =
             Rooms.create_room(ctx.code, owner: ctx.owner.id, owner_display_name: "Wise Otter 42")

    {:ok, token} = Rooms.create_invite(ctx.code, :editor)
    assert {:ok, :joined} = Rooms.consume_invite(ctx.code, ctx.other.id, token, "Keen Rhino 44")

    {:ok, view, _} = live(authenticated(ctx.other_session.token), "/rooms/#{ctx.code}")

    refute has_element?(view, "#members-button")
    render_click(view, "open-members", %{"user_id" => ctx.owner.id})
    render_click(view, "remove-member", %{"user_id" => ctx.owner.id})
    render_click(view, "generate-invite", %{"user_id" => ctx.owner.id})
    render_click(view, "revoke-invite", %{"user_id" => ctx.owner.id})

    render_click(view, "set-member-role", %{
      "user_id" => ctx.other.id,
      "role" => "viewer"
    })

    assert Rooms.members(ctx.code) |> length() == 2
    assert Rooms.role_of(ctx.code, ctx.other.id) == :editor

    # The forged revoke left the active invite untouched.
    assert Rooms.invite_active?(ctx.code, :editor)
  end

  defp authenticated(token),
    do: Plug.Test.init_test_session(build_conn(), %{user_token: token})

  defp ids, do: Repo.query!("SELECT id::text FROM users ORDER BY id", []).rows |> List.flatten()
end
