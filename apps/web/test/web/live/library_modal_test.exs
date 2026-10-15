defmodule Web.LibraryModalTest do
  use Web.ConnCase, async: false

  alias Analysis.Analysis, as: AnalysisModel
  alias Analysis.AnalysisStore
  alias Analysis.UserLibrary
  alias Analysis.UserSessions
  alias Analysis.Users
  alias OpenChessLab.Repo

  setup do
    before_ids = ids()
    {:ok, user} = Users.create()
    {:ok, other} = Users.create()
    {:ok, session} = UserSessions.create(user.id)
    suffix = Base.encode16(:crypto.strong_rand_bytes(6))
    own = "own-#{suffix}"
    theirs = "theirs-#{suffix}"
    for id <- [own, theirs], do: AnalysisStore.insert(AnalysisModel.new(id, 42))
    :ok = UserLibrary.save(user.id, own)
    :ok = UserLibrary.save(other.id, own)
    :ok = UserLibrary.save(other.id, theirs)

    on_exit(fn ->
      for id <- [own, theirs], do: AnalysisStore.delete(id, 1)
      Enum.each(ids() -- before_ids, &Users.delete/1)
    end)

    %{user: user, other: other, session: session, own: own, theirs: theirs}
  end

  test "the modal renders only the authenticated user's references, including in Dutch", ctx do
    {:ok, view, _} = live(put_req_cookie(authenticated(ctx), "_ocl_locale", "nl"), "/")
    render_click(view, "open-library", %{"user_id" => ctx.other.id})

    assert has_element?(view, "#library-modal-title", "Mijn bibliotheek")
    assert has_element?(view, "#library-entries li", ctx.own)
    refute render(view) =~ ctx.theirs
    refute render(view) =~ ctx.session.token
  end

  test "guests and forged identities only receive the login variant", ctx do
    {:ok, view, _} = live(build_conn(), "/")
    render_click(view, "open-library", %{"user_id" => ctx.user.id})

    assert has_element?(view, "#library-modal-title")
    assert render(view) =~ Web.I18n.t("auth.loginRequired", "en")
    refute has_element?(view, "#library-entries")
    refute render(view) =~ ctx.own
  end

  test "removal cannot select another user and leaves the shared analysis intact", ctx do
    {:ok, view, _} = live(authenticated(ctx), "/")
    render_click(view, "open-library")

    render_click(view, "library-remove", %{"id" => ctx.theirs, "user_id" => ctx.other.id})
    assert ctx.theirs in UserLibrary.list(ctx.other.id)

    render_click(view, "library-remove", %{"id" => ctx.own, "user_id" => ctx.other.id})
    assert UserLibrary.list(ctx.user.id) == []
    assert ctx.own in UserLibrary.list(ctx.other.id)
    assert {:ok, _, 1} = AnalysisStore.get(ctx.own)
    assert has_element?(view, "#library-empty")
  end

  test "a revoked credential fails closed on modal actions", ctx do
    {:ok, view, _} = live(authenticated(ctx), "/")
    render_click(view, "open-library")
    UserSessions.revoke(ctx.session.token)

    render_click(view, "library-remove", %{"id" => ctx.own, "user_id" => ctx.user.id})
    assert ctx.own in UserLibrary.list(ctx.user.id)

    render_click(view, "open-library")
    assert render(view) =~ Web.I18n.t("auth.loginRequired", "en")
    refute has_element?(view, "#library-entries")
  end

  test "rename uses the selected personal entry, persists and escapes the title", ctx do
    {:ok, view, _} = live(authenticated(ctx), "/")
    render_click(view, "open-library")

    assert has_element?(
             view,
             "#saved-#{ctx.own} button[phx-click='library-open']",
             "Untitled analysis"
           )

    render_click(view, "library-start-rename", %{"id" => ctx.own})

    render_submit(view, "library-rename", %{
      "title" => "  My <script>plan</script>  ",
      "id" => ctx.theirs,
      "user_id" => ctx.other.id
    })

    assert {:ok, "My <script>plan</script>"} = UserLibrary.title(ctx.user.id, ctx.own)
    assert {:ok, nil} = UserLibrary.title(ctx.other.id, ctx.own)
    assert {:ok, nil} = UserLibrary.title(ctx.other.id, ctx.theirs)

    assert has_element?(
             view,
             "#saved-#{ctx.own} button[phx-click='library-open']",
             "My <script>plan</script>"
           )

    refute has_element?(view, "#library-entries script")
    refute has_element?(view, "#library-rename-form")

    render_click(view, "close-modal")
    render_click(view, "open-library")

    assert has_element?(
             view,
             "#saved-#{ctx.own} button[phx-click='library-open']",
             "My <script>plan</script>"
           )
  end

  test "invalid titles stay editable; cancellation and clearing work in Dutch", ctx do
    {:ok, view, _} = live(put_req_cookie(authenticated(ctx), "_ocl_locale", "nl"), "/")
    render_click(view, "open-library")

    render_click(view, "library-start-rename", %{"id" => ctx.own})
    assert has_element?(view, "label[for='library-title']", "Analysetitel")

    render_submit(view, "library-rename", %{"title" => String.duplicate("x", 121)})
    assert has_element?(view, "#library-rename-form [role='alert']", "maximaal 120")
    assert {:ok, nil} = UserLibrary.title(ctx.user.id, ctx.own)

    render_click(view, "library-cancel-rename", %{})
    refute has_element?(view, "#library-rename-form")

    render_click(view, "library-start-rename", %{"id" => ctx.own})
    render_submit(view, "library-rename", %{"title" => "Mijn analyse"})

    render_click(view, "library-start-rename", %{"id" => ctx.own})
    render_submit(view, "library-rename", %{"title" => "  "})

    assert has_element?(
             view,
             "#saved-#{ctx.own} button[phx-click='library-open']",
             "Analyse zonder titel"
           )
  end

  test "the library modal opens over a room without disrupting it", ctx do
    code = "LM" <> Base.encode16(:crypto.strong_rand_bytes(2))
    {:ok, _room} = Analysis.Rooms.start_room(code)
    on_exit(fn -> Analysis.Rooms.stop_room(code) end)

    {:ok, view, _} = live(authenticated(ctx), "/rooms/#{code}")
    assert has_element?(view, "button[phx-click='create-analysis']")

    render_click(view, "open-library", %{"user_id" => ctx.other.id})
    assert has_element?(view, "#library-modal-title")
    assert has_element?(view, "#library-entries li", ctx.own)
    refute render(view) =~ ctx.theirs
    assert has_element?(view, "button[phx-click='create-analysis']")

    render_click(view, "close-modal")
    refute has_element?(view, "#library-modal-title")
    assert has_element?(view, "button[phx-click='create-analysis']")
  end

  defp authenticated(ctx),
    do: Plug.Test.init_test_session(build_conn(), %{user_token: ctx.session.token})

  defp ids, do: Repo.query!("SELECT id::text FROM users ORDER BY id", []).rows |> List.flatten()
end
