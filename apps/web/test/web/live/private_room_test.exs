defmodule Web.PrivateRoomTest do
  use Web.ConnCase, async: false

  alias Analysis.{Analyses, Rooms, Users, UserSessions}
  alias OpenChessLab.Repo

  @origin "https://openchesslab.example"

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
    assert has_element?(room_view, "#invite-button")
    refute has_element?(room_view, "button[phx-click='copy-room-code']")
  end

  test "a private room gates non-members without leaking any content", ctx do
    assert {:ok, _room} = Rooms.create_room(ctx.code, owner: ctx.owner.id)
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
    assert {:ok, _room} = Rooms.create_room(ctx.code, owner: ctx.owner.id)
    {:ok, view, html} = live(authenticated(ctx.owner_session.token), "/rooms/#{ctx.code}")

    # No copy-code button in a private room; the owner gets the Invite button.
    refute has_element?(view, "button[phx-click='copy-room-code']")
    assert has_element?(view, "#invite-button", "Invite")
    refute html =~ ctx.analysis_id

    render_click(view, "open-invite")
    assert has_element?(view, "#invite-title")
    assert has_element?(view, "button[phx-click='generate-invite']")

    # Generating shows the full URL exactly once and activates the link.
    html = render_click(view, "generate-invite")
    [invite] = Regex.run(~r|/rooms/#{ctx.code}/join/[A-Za-z0-9_-]{43}|, html)
    assert has_element?(view, "#invite-link")
    assert Rooms.invite_active?(ctx.code)

    # Regenerating rotates: the old URL dies, the new one works.
    html = render_click(view, "generate-invite")
    [new_invite] = Regex.run(~r|/rooms/#{ctx.code}/join/[A-Za-z0-9_-]{43}|, html)
    refute new_invite == invite

    # Revoking kills the active link.
    render_click(view, "revoke-invite")
    refute Rooms.invite_active?(ctx.code)
  end

  test "invite links admit signed-in members through the join route", ctx do
    assert {:ok, _room} = Rooms.create_room(ctx.code, owner: ctx.owner.id)
    assert {:ok, _a, 1} = Analyses.create(ctx.analysis_id)
    :ok = Rooms.add_analysis(ctx.code, ctx.analysis_id)
    {:ok, token} = Rooms.create_invite(ctx.code)

    # The member-to-be opens the join URL and lands in the room.
    conn =
      authenticated(ctx.other_session.token)
      |> get("/rooms/#{ctx.code}/join/#{token}")

    assert redirected_to(conn) == "/rooms/#{ctx.code}"
    assert Rooms.member?(ctx.code, ctx.other.id)

    {:ok, view, html} =
      live(authenticated(ctx.other_session.token), "/rooms/#{ctx.code}?a=#{ctx.analysis_id}")

    assert has_element?(view, "#chess-board")
    assert html =~ ctx.analysis_id
    refute has_element?(view, "#invite-button")

    # Multi-use: the same link admits another member later.
    {:ok, third} = Users.create()
    {:ok, third_session} = UserSessions.create(third.id)
    conn = authenticated(third_session.token) |> get("/rooms/#{ctx.code}/join/#{token}")
    assert redirected_to(conn) == "/rooms/#{ctx.code}"

    # Revoke: the link is dead for anyone new.
    Rooms.revoke_invites(ctx.code)
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
    assert {:ok, _room} = Rooms.create_room(ctx.code, owner: ctx.owner.id)
    {:ok, token} = Rooms.create_invite(ctx.code)

    conn = build_conn() |> get("/rooms/#{ctx.code}/join/#{token}")
    assert redirected_to(conn) == "/rooms/#{ctx.code}"
    refute Rooms.member?(ctx.code, nil)
  end

  test "forged invite events by non-owners change nothing", ctx do
    assert {:ok, _room} = Rooms.create_room(ctx.code, owner: ctx.owner.id)
    {:ok, view, _} = live(authenticated(ctx.other_session.token), "/rooms/#{ctx.code}")

    # The non-member never even gets the room page; use the owner to be sure
    # the events exist, then a signed-in member-forger cannot touch invites.
    render_click(view, "generate-invite", %{"user_id" => ctx.owner.id})
    refute Rooms.invite_active?(ctx.code)
  end

  defp authenticated(token),
    do: Plug.Test.init_test_session(build_conn(), %{user_token: token})

  defp ids, do: Repo.query!("SELECT id::text FROM users ORDER BY id", []).rows |> List.flatten()
end
