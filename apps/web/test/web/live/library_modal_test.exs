defmodule Web.LibraryModalTest do
  use Web.ConnCase, async: false

  alias Analysis.Analysis, as: AnalysisModel
  alias Analysis.AnalysisStore
  alias Analysis.Rooms
  alias Analysis.UserLibrary
  alias Analysis.UserSessions
  alias Analysis.Users

  setup do
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
      Users.delete(user.id)
      Users.delete(other.id)
      for id <- [own, theirs], do: AnalysisStore.delete(id, 1)
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

  test "the removed /library and /account routes are gone", ctx do
    for path <- ["/library", "/account"] do
      assert response(get(authenticated(ctx), path), 404)
    end
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

  test "paging ignores submitted user and cursor values and keeps at most 50 entries", ctx do
    ids = for n <- 1..51, do: "page-#{ctx.own}-#{String.pad_leading(to_string(n), 3, "0")}"
    on_exit(fn -> for id <- ids, do: AnalysisStore.delete(id, 1) end)

    for id <- ids do
      {:ok, 1} = AnalysisStore.insert(AnalysisModel.new(id, 42))
      :ok = UserLibrary.save(ctx.user.id, id)
    end

    {:ok, view, _} = live(authenticated(ctx), "/")
    render_click(view, "open-library")

    assert length(:sys.get_state(view.pid).socket.assigns.library_entries) == 50
    assert has_element?(view, "button[phx-click='library-next-page']")

    render_click(view, "library-next-page", %{"user_id" => ctx.other.id, "cursor" => ctx.theirs})

    assert length(:sys.get_state(view.pid).socket.assigns.library_entries) == 2
    assert has_element?(view, "#library-entries li", List.last(ids))
    refute render(view) =~ ctx.theirs
    refute has_element?(view, "button[phx-click='library-next-page']")

    render_click(view, "library-first-page", %{})
    assert has_element?(view, "#library-entries li", ctx.own)
  end

  test "rename uses the selected personal entry, persists and escapes the title", ctx do
    {:ok, view, _} = live(authenticated(ctx), "/")
    render_click(view, "open-library")
    assert has_element?(view, "#saved-#{ctx.own} a", "Untitled analysis")

    render_click(view, "library-start-rename", %{"id" => ctx.own})

    render_submit(view, "library-rename", %{
      "title" => "  My <script>plan</script>  ",
      "id" => ctx.theirs,
      "user_id" => ctx.other.id
    })

    assert {:ok, "My <script>plan</script>"} = UserLibrary.title(ctx.user.id, ctx.own)
    assert {:ok, nil} = UserLibrary.title(ctx.other.id, ctx.own)
    assert {:ok, nil} = UserLibrary.title(ctx.other.id, ctx.theirs)
    assert has_element?(view, "#saved-#{ctx.own} a", "My <script>plan</script>")
    refute has_element?(view, "#library-entries script")
    refute has_element?(view, "#library-rename-form")

    render_click(view, "close-modal")
    render_click(view, "open-library")
    assert has_element?(view, "#saved-#{ctx.own} a", "My <script>plan</script>")
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
    assert has_element?(view, "#saved-#{ctx.own} a", "Analyse zonder titel")
  end

  test "foreign selections and removed entries cannot be renamed", ctx do
    {:ok, view, _} = live(authenticated(ctx), "/")
    render_click(view, "open-library")

    render_click(view, "library-start-rename", %{"id" => ctx.theirs, "user_id" => ctx.other.id})
    refute has_element?(view, "#library-rename-form")

    render_submit(view, "library-rename", %{"title" => "Denied", "id" => ctx.theirs})
    assert {:ok, nil} = UserLibrary.title(ctx.other.id, ctx.theirs)

    render_click(view, "library-start-rename", %{"id" => ctx.own})
    UserLibrary.remove(ctx.user.id, ctx.own)

    render_submit(view, "library-rename", %{"title" => "Removed"})

    assert {:ok, nil} = UserLibrary.title(ctx.other.id, ctx.own)
  end

  test "the library modal opens over a room without disrupting it", ctx do
    code = "LM" <> Base.encode16(:crypto.strong_rand_bytes(2))
    {:ok, _room} = Rooms.start_room(code)
    on_exit(fn -> Rooms.stop_room(code) end)

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
end
