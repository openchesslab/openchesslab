defmodule Web.LibraryTrackingTest do
  use Web.ConnCase, async: false

  alias Analysis.{Analyses, AnalysisStore, RoomStore, UserLibrary, UserSessions, Users}
  alias OpenChessLab.Repo

  setup do
    before_ids = ids()
    {:ok, user} = Users.create()
    {:ok, other} = Users.create()
    {:ok, session} = UserSessions.create(user.id)
    code = "TRK" <> Base.encode16(:crypto.strong_rand_bytes(2))
    id = "star-" <> Base.encode16(:crypto.strong_rand_bytes(6))
    {:ok, _, 1} = Analyses.create(id)
    :ok = RoomStore.create(code)
    :ok = RoomStore.add_analysis(code, id)

    on_exit(fn ->
      RoomStore.delete(code)
      Repo.query!("DELETE FROM analyses WHERE analysis_id = $1", [id])
      Enum.each(ids() -- before_ids, &Users.delete/1)
    end)

    %{user: user, other: other, session: session, code: code, id: id}
  end

  test "the star tracks the room analysis as a live reference", ctx do
    {:ok, view, _} = live(authenticated(ctx), "/rooms/#{ctx.code}?a=#{ctx.id}")
    star = "#track-#{ctx.id}"
    assert has_element?(view, "#{star}[aria-pressed='false']")

    render_click(view, "track-analysis", %{"id" => ctx.id, "user_id" => ctx.other.id})
    assert has_element?(view, "#{star}[aria-pressed='true']")
    assert UserLibrary.list(ctx.user.id) == [ctx.id]
    assert UserLibrary.list(ctx.other.id) == []

    render_click(view, "untrack-analysis", %{"id" => ctx.id, "user_id" => ctx.other.id})
    assert has_element?(view, "#{star}[aria-pressed='false']")
    assert UserLibrary.list(ctx.user.id) == []
    assert {:ok, _, 1} = AnalysisStore.get(ctx.id)
  end

  test "the library tab lists a tracked analysis; the private editor refuses it", ctx do
    assert {:ok, :tracked} = UserLibrary.track_from_room(ctx.user.id, ctx.code, ctx.id)

    {:ok, view, _} = live(authenticated(ctx), "/rooms/#{ctx.code}?a=#{ctx.id}")
    render_click(view, "open-import", %{})
    render_click(view, "set-import-source", %{"source" => "library"})

    assert has_element?(view, "#library-entries li", ctx.id)
    assert has_element?(view, "a[href='/library/#{ctx.id}']")

    # A live reference is still the room's shared analysis: the private
    # editor refuses it until branching materializes a private copy.
    assert {:error, {:redirect, %{to: "/"}}} = live(authenticated(ctx), "/library/#{ctx.id}")
  end

  test "guests and revoked sessions cannot track, even with forged parameters", ctx do
    {:ok, guest, _} = live(build_conn(), "/rooms/#{ctx.code}?a=#{ctx.id}")
    refute has_element?(guest, "#track-#{ctx.id}")

    render_click(guest, "track-analysis", %{"id" => ctx.id, "user_id" => ctx.user.id})
    assert UserLibrary.list(ctx.user.id) == []

    {:ok, signed_in, _} = live(authenticated(ctx), "/rooms/#{ctx.code}?a=#{ctx.id}")
    UserSessions.revoke(ctx.session.token)

    render_click(signed_in, "track-analysis", %{"id" => ctx.id, "user_id" => ctx.user.id})
    assert UserLibrary.list(ctx.user.id) == []
  end

  test "removed room analyses cannot be tracked", ctx do
    {:ok, view, _} = live(authenticated(ctx), "/rooms/#{ctx.code}?a=#{ctx.id}")
    RoomStore.remove_analysis(ctx.code, ctx.id)

    render_click(view, "track-analysis", %{"id" => ctx.id, "user_id" => ctx.user.id})

    assert UserLibrary.list(ctx.user.id) == []
    assert render(view) =~ "Could not add this analysis to your library"
  end

  defp authenticated(ctx),
    do: Plug.Test.init_test_session(build_conn(), %{user_token: ctx.session.token})

  defp ids, do: Repo.query!("SELECT id::text FROM users ORDER BY id", []).rows |> List.flatten()
end
