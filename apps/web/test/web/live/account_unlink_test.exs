defmodule Web.AccountUnlinkTest do
  use Web.ConnCase, async: false

  alias Analysis.{Accounts, Rooms, UserSessions, Users}
  alias OpenChessLab.Repo

  @origin "https://openchesslab.example"
  @lichess %{client_id: "lichess-client", redirect_uri: @origin <> "/auth/lichess/callback"}
  @google %{
    client_id: "google-client",
    client_secret: "private-secret",
    redirect_uri: @origin <> "/auth/google/callback"
  }

  setup do
    settings =
      Map.new(
        [:lichess_oauth, :google_oauth],
        &{&1, Application.fetch_env(:web, &1)}
      )

    before_ids = ids()
    {:ok, user} = Users.create()
    {:ok, _} = Accounts.link_verified(user.id, "lichess", "unlink-lichess-subject")
    {:ok, _} = Accounts.link_verified(user.id, "google", "unlink-google-subject")
    {:ok, session} = UserSessions.create(user.id)
    Application.put_env(:web, :lichess_oauth, @lichess)
    Application.put_env(:web, :google_oauth, @google)

    on_exit(fn ->
      Enum.each(ids() -- before_ids, &Users.delete/1)

      Enum.each(settings, fn
        {key, {:ok, value}} -> Application.put_env(:web, key, value)
        {key, :error} -> Application.delete_env(:web, key)
      end)
    end)

    %{user: user, session: session}
  end

  test "a connected provider can be unlinked from the account modal without leaving the room",
       ctx do
    code = "UL" <> Base.encode16(:crypto.strong_rand_bytes(2))
    {:ok, _room} = Rooms.start_room(code)
    on_exit(fn -> Rooms.stop_room(code) end)

    {:ok, view, _} = live(signed_in(ctx.session.token), "/rooms/#{code}")
    render_click(view, "open-account")

    assert has_element?(view, "#unlink-lichess", "Unlink Lichess")
    assert has_element?(view, "#unlink-google", "Unlink Google")

    render_click(view, "unlink-provider", %{"provider" => "lichess", "user_id" => ctx.user.id})

    refute has_element?(view, "#unlink-lichess")
    assert has_element?(view, "#link-lichess", "Connect Lichess")
    assert has_element?(view, "#unlink-google", "Unlink Google")
    assert Accounts.providers_for(ctx.user.id) == ["google"]
    assert {:ok, _} = UserSessions.user_for_token(ctx.session.token)
    assert has_element?(view, "#account-modal-title")
  end

  test "the last remaining provider cannot be unlinked and reports why", ctx do
    assert {:ok, 1} = Accounts.unlink(ctx.user.id, "google")

    {:ok, view, _} = live(signed_in(ctx.session.token), "/")
    render_click(view, "open-account")
    assert has_element?(view, "#unlink-lichess")

    render_click(view, "unlink-provider", %{"provider" => "lichess"})

    assert has_element?(view, "#account-error", "Keep at least one account connected")
    assert has_element?(view, "#unlink-lichess")
    assert Accounts.providers_for(ctx.user.id) == ["lichess"]
  end

  test "guest and revoked events fail closed", ctx do
    {:ok, guest, _} = live(build_conn(), "/")
    render_click(guest, "unlink-provider", %{"provider" => "lichess", "user_id" => ctx.user.id})
    assert Accounts.providers_for(ctx.user.id) == ["google", "lichess"]

    {:ok, view, _} = live(signed_in(ctx.session.token), "/")
    render_click(view, "open-account")
    UserSessions.revoke(ctx.session.token)
    render_click(view, "unlink-provider", %{"provider" => "lichess", "user_id" => ctx.user.id})
    assert Accounts.providers_for(ctx.user.id) == ["google", "lichess"]
  end

  defp signed_in(token), do: Plug.Test.init_test_session(build_conn(), %{user_token: token})
  defp ids, do: Repo.query!("SELECT id::text FROM users ORDER BY id", []).rows |> List.flatten()
end
