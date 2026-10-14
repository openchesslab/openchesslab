defmodule Web.AccountDeletionTest do
  use Web.ConnCase, async: false

  alias Analysis.{Accounts, Analysis, AnalysisStore, UserLibrary, UserSessions, Users}
  alias OpenChessLab.Repo

  @origin "https://openchesslab.example"

  setup do
    before_ids = ids()
    {:ok, user} = Users.create()
    {:ok, _} = Accounts.link_verified(user.id, "lichess", "lichess-subject")
    {:ok, session} = UserSessions.create(user.id)
    {:ok, other_tab} = UserSessions.create(user.id)
    analysis_id = "deletion-" <> Ecto.UUID.generate()
    {:ok, 1} = AnalysisStore.insert(Analysis.new(analysis_id, 42))
    :ok = UserLibrary.save(user.id, analysis_id)

    on_exit(fn ->
      AnalysisStore.delete(analysis_id, 1)
      Enum.each(ids() -- before_ids, &Users.delete/1)
    end)

    %{user: user, session: session, other_tab: other_tab, analysis_id: analysis_id}
  end

  test "typed confirmation deletes identities, sessions and library links, not analyses", ctx do
    page = delete_page(ctx.session.token)
    csrf = form_csrf(page, "account-delete-form")

    result =
      page
      |> recycle()
      |> put_private(:plug_skip_csrf_protection, false)
      |> post(@origin <> "/account/delete", %{
        "_csrf_token" => csrf,
        "confirmation" => " delete "
      })

    assert redirected_to(result) == "/"
    assert get_session(result, :user_token) == nil
    assert :not_found = Users.get(ctx.user.id)
    assert :not_found = UserSessions.user_for_token(ctx.session.token)
    assert :not_found = UserSessions.user_for_token(ctx.other_tab.token)
    assert :not_found = Accounts.user_for_verified_identity("lichess", "lichess-subject")
    assert Accounts.providers_for(ctx.user.id) == []

    assert [[0]] ==
             Repo.query!("SELECT count(*) FROM user_analyses WHERE user_id = $1", [
               Ecto.UUID.dump!(ctx.user.id)
             ]).rows

    assert {:ok, %Analysis{}, 1} = AnalysisStore.get(ctx.analysis_id)
  end

  test "wrong or missing confirmation preserves the account and session", ctx do
    for confirmation <- ["remove", "delete!", "", nil, ["DELETE"]] do
      page = delete_page(ctx.session.token)
      csrf = form_csrf(page, "account-delete-form")

      result =
        page
        |> recycle()
        |> put_private(:plug_skip_csrf_protection, false)
        |> post(@origin <> "/account/delete", %{
          "_csrf_token" => csrf,
          "confirmation" => confirmation
        })

      assert redirected_to(result) == "/account"
      assert Phoenix.Flash.get(result.assigns.flash, :error) =~ "confirmation word"

      assert {:ok, %{id: user_id}} = UserSessions.user_for_token(ctx.session.token)
      assert user_id == ctx.user.id
    end
  end

  test "a deleted account frees its provider identity for another account", ctx do
    {:ok, keeper} = Users.create()
    {:ok, _} = Accounts.link_verified(keeper.id, "lichess", "keeper-subject")
    {:ok, _} = Accounts.link_verified(ctx.user.id, "google", "google-subject")
    {:ok, google_session} = UserSessions.create(ctx.user.id)

    assert {:error, :already_linked} =
             Accounts.link_verified(keeper.id, "google", "google-subject")

    page = delete_page(google_session.token)
    csrf = form_csrf(page, "account-delete-form")

    result =
      page
      |> recycle()
      |> put_private(:plug_skip_csrf_protection, false)
      |> post(@origin <> "/account/delete", %{
        "_csrf_token" => csrf,
        "confirmation" => "verwijder"
      })

    assert redirected_to(result) == "/"
    assert :not_found = Accounts.user_for_verified_identity("google", "google-subject")

    assert {:ok, account_id} =
             Accounts.link_verified(keeper.id, "google", "google-subject")

    assert is_integer(account_id)
    assert Accounts.providers_for(keeper.id) == ["google", "lichess"]
  end

  test "anonymous and CSRF-less deletion requests are rejected", ctx do
    home =
      build_conn()
      |> put_private(:plug_skip_csrf_protection, false)
      |> get(@origin <> "/")

    [_, csrf] =
      Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, html_response(home, 200))

    anonymous =
      home
      |> recycle()
      |> put_private(:plug_skip_csrf_protection, false)
      |> post(@origin <> "/account/delete", %{
        "_csrf_token" => csrf,
        "confirmation" => "DELETE"
      })

    assert redirected_to(anonymous) == "/"
    assert Phoenix.Flash.get(anonymous.assigns.flash, :error) =~ "log in"
    assert {:ok, _} = Users.get(ctx.user.id)

    assert_error_sent 403, fn ->
      signed_in(ctx.session.token)
      |> put_private(:plug_skip_csrf_protection, false)
      |> post(@origin <> "/account/delete", %{"confirmation" => "DELETE"})
    end

    assert {:ok, _} = UserSessions.user_for_token(ctx.session.token)
  end

  test "account page shows the deletion danger zone in both languages", ctx do
    {:ok, view, html} = live(signed_in(ctx.session.token), "/account")
    assert has_element?(view, "#account-danger-zone")
    assert has_element?(view, "#account-delete-form[action='/account/delete'][method='post']")
    assert has_element?(view, "#account-delete-form input[name='_csrf_token']")
    assert has_element?(view, "#account-delete-confirmation[name='confirmation']")
    assert has_element?(view, "#account-delete-confirmation[placeholder='DELETE']")
    assert html =~ "Type DELETE to confirm"

    {:ok, view_nl, html_nl} = live(signed_in(ctx.session.token), "/account?locale=nl")
    assert has_element?(view_nl, "#account-delete-confirmation[placeholder='VERWIJDER']")
    assert html_nl =~ "Typ VERWIJDER om te bevestigen"
  end

  defp delete_page(token),
    do:
      signed_in(token)
      |> put_private(:plug_skip_csrf_protection, false)
      |> get(@origin <> "/account")

  defp form_csrf(conn, id) do
    [token] =
      conn
      |> html_response(200)
      |> LazyHTML.from_document()
      |> LazyHTML.query("##{id} input[name='_csrf_token']")
      |> LazyHTML.attribute("value")

    token
  end

  defp signed_in(token), do: Plug.Test.init_test_session(build_conn(), %{user_token: token})
  defp ids, do: Repo.query!("SELECT id::text FROM users ORDER BY id", []).rows |> List.flatten()
end
