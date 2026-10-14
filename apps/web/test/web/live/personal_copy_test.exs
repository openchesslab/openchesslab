defmodule Web.PersonalCopyTest do
  use Web.ConnCase, async: false

  alias Analysis.Analyses
  alias Analysis.AnalysisStore
  alias Analysis.Rooms
  alias Analysis.RoomStore
  alias Analysis.UserLibrary
  alias Analysis.Users
  alias Analysis.UserSessions
  alias OpenChessLab.Repo

  setup do
    {:ok, user} = Users.create()
    {:ok, other} = Users.create()
    {:ok, session} = UserSessions.create(user.id)
    code = "CP" <> Base.encode16(:crypto.strong_rand_bytes(6))
    id = "source-" <> Ecto.UUID.generate()
    {:ok, _, 1} = Analyses.create(id)
    {:ok, _} = Rooms.create_room(code)
    :ok = Rooms.add_analysis(code, id)

    on_exit(fn ->
      for owner <- [user, other] do
        for copy <- UserLibrary.list(owner.id),
            do: Repo.query!("DELETE FROM analyses WHERE analysis_id = $1", [copy])

        Users.delete(owner.id)
      end

      Rooms.stop_room(code)
      Repo.query!("DELETE FROM analyses WHERE analysis_id = $1", [id])
    end)

    %{user: user, other: other, session: session, code: code, id: id}
  end

  test "signed-in users save the selected analysis, ignoring forged owner/room/source parameters",
       ctx do
    {:ok, view, _} =
      live(
        authenticated(ctx) |> put_req_cookie("_ocl_locale", "nl"),
        "/rooms/#{ctx.code}?a=#{ctx.id}"
      )

    assert has_element?(view, "#save-personal-copy", "Bewaar een persoonlijke kopie")
    render_click(view, "save-comment", %{"comment" => "Snapshot comment"})

    html =
      render_click(view, "save-personal-copy", %{
        "user_id" => ctx.other.id,
        "room_id" => "other-room",
        "analysis_id" => "other-analysis"
      })

    assert html =~ "Persoonlijke kopie bewaard in Mijn bibliotheek."
    assert [copy_id] = UserLibrary.list(ctx.user.id)
    assert UserLibrary.list(ctx.other.id) == []
    assert {:ok, source, _} = AnalysisStore.get(ctx.id)
    assert {:ok, copy, 1} = AnalysisStore.get(copy_id)
    assert %{copy | id: source.id} == source
    assert {:ok, room} = Rooms.get(ctx.code)
    assert room.analysis_ids == [ctx.id]
    assert :sys.get_state(view.pid).socket.assigns.selected_analysis_id == ctx.id

    render_click(view, "save-comment", %{"comment" => "Later shared comment"})
    assert {:ok, ^copy, 1} = AnalysisStore.get(copy_id)
    {:ok, library, _} = live(authenticated(ctx), "/library")
    assert has_element?(library, "#library-entries li", copy_id)
    refute has_element?(library, "#library-entries li", ctx.id)
  end

  test "guests and revoked sessions cannot save, even with forged identity parameters", ctx do
    {:ok, guest, _} = live(build_conn(), "/rooms/#{ctx.code}?a=#{ctx.id}")
    refute has_element?(guest, "#save-personal-copy")

    assert render_click(guest, "save-personal-copy", %{"user_id" => ctx.user.id}) =~
             "Log in to save a personal copy."

    {:ok, signed_in, _} = live(authenticated(ctx), "/rooms/#{ctx.code}?a=#{ctx.id}")
    UserSessions.revoke(ctx.session.token)

    assert render_click(signed_in, "save-personal-copy", %{"user_id" => ctx.user.id}) =~
             "Log in to save a personal copy."

    refute has_element?(signed_in, "#save-personal-copy")
    assert UserLibrary.list(ctx.user.id) == []
  end

  test "removed durable membership prevents copying even while the LiveView still has the analysis",
       ctx do
    {:ok, view, _} = live(authenticated(ctx), "/rooms/#{ctx.code}?a=#{ctx.id}")
    RoomStore.remove_analysis(ctx.code, ctx.id)
    assert render_click(view, "save-personal-copy", %{}) =~ "Could not save a personal copy."
    assert UserLibrary.list(ctx.user.id) == []
  end

  test "a personal copy cannot be opened through room URLs or selection events", ctx do
    {:ok, copy_id} = UserLibrary.copy_from_room(ctx.user.id, ctx.code, ctx.id)
    Analyses.set_comment(copy_id, [], "Secret personal note")
    conn = get(build_conn(), "/rooms/#{ctx.code}?a=#{copy_id}")
    refute html_response(conn, 302) =~ "Secret personal note"
    destination = redirected_to(conn)
    assert destination == "/rooms/#{ctx.code}?a=#{ctx.id}"
    {:ok, view, html} = live(build_conn(), destination)
    refute html =~ "Secret personal note"
    assert :sys.get_state(view.pid).socket.assigns.selected_analysis_id == ctx.id
    refute render_click(view, "select-analysis", %{"id" => copy_id}) =~ "Secret personal note"
    # The normal follow-viewer event must also respect room membership.
    refute render_click(view, "follow-viewer", %{"analysis_id" => copy_id, "path" => ""}) =~
             "Secret personal note"

    assert :sys.get_state(view.pid).socket.assigns.selected_analysis_id == ctx.id
  end

  defp authenticated(ctx),
    do: Plug.Test.init_test_session(build_conn(), %{user_token: ctx.session.token})
end
