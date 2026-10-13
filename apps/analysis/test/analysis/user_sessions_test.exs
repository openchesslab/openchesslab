defmodule Analysis.UserSessionsTest do
  use ExUnit.Case, async: false

  alias Analysis.Users
  alias Analysis.UserSessions
  alias OpenChessLab.Repo

  setup do
    {:ok, user} = Users.create()
    {:ok, other} = Users.create()

    on_exit(fn ->
      Users.delete(user.id)
      Users.delete(other.id)
    end)

    %{user: user, other: other}
  end

  test "fresh credentials resolve independently and only hashes are stored", %{user: user} do
    assert {:ok, first} = UserSessions.create(user.id)
    assert {:ok, second} = UserSessions.create(user.id)
    refute first.token == second.token
    assert {:ok, raw} = Base.url_decode64(first.token, padding: false)
    assert byte_size(raw) == 32
    assert {:ok, ^user} = UserSessions.user_for_token(first.token)
    assert {:ok, ^user} = UserSessions.user_for_token(second.token)

    rows =
      Repo.query!(
        "SELECT token_hash, created_at, expires_at FROM user_sessions WHERE user_id = $1",
        [Ecto.UUID.dump!(user.id)]
      ).rows

    assert length(rows) == 2

    for [hash, created_at, expires_at] <- rows do
      assert hash in [:crypto.hash(:sha256, first.token), :crypto.hash(:sha256, second.token)]
      assert byte_size(hash) == 32
      assert NaiveDateTime.diff(expires_at, created_at) == 86_400
    end

    [[columns]] =
      Repo.query!(
        "SELECT array_agg(column_name ORDER BY column_name) FROM information_schema.columns WHERE table_name = 'user_sessions' AND table_schema = current_schema()",
        []
      ).rows

    assert columns == ["created_at", "expires_at", "token_hash", "user_id"]
  end

  test "lookup never extends expiry and expired sessions are rejected", %{user: user} do
    {:ok, session} = UserSessions.create(user.id)
    assert {:ok, ^user} = UserSessions.user_for_token(session.token)

    assert [[session.expires_at]] ==
             Repo.query!("SELECT expires_at FROM user_sessions WHERE user_id = $1", [
               Ecto.UUID.dump!(user.id)
             ]).rows

    Repo.query!(
      "UPDATE user_sessions SET created_at = timezone('UTC', statement_timestamp()) - interval '2 days', expires_at = timezone('UTC', statement_timestamp()) - interval '1 second' WHERE user_id = $1",
      [Ecto.UUID.dump!(user.id)]
    )

    assert :not_found = UserSessions.user_for_token(session.token)
    assert :ok = UserSessions.revoke(session.token)

    assert [[0]] ==
             Repo.query!("SELECT count(*) FROM user_sessions WHERE user_id = $1", [
               Ecto.UUID.dump!(user.id)
             ]).rows
  end

  test "revocation is idempotent and isolated from other sessions", %{user: user, other: other} do
    {:ok, first} = UserSessions.create(user.id)
    {:ok, second} = UserSessions.create(user.id)
    {:ok, unrelated} = UserSessions.create(other.id)

    assert :ok = UserSessions.revoke(first.token)
    assert :ok = UserSessions.revoke(first.token)
    assert :not_found = UserSessions.user_for_token(first.token)
    assert {:ok, ^user} = UserSessions.user_for_token(second.token)
    assert {:ok, ^other} = UserSessions.user_for_token(unrelated.token)

    assert :ok = UserSessions.revoke_all(user.id)
    assert :ok = UserSessions.revoke_all(user.id)
    assert :not_found = UserSessions.user_for_token(second.token)
    assert {:ok, ^other} = UserSessions.user_for_token(unrelated.token)
  end

  test "deleting a user invalidates and removes all their sessions", %{user: user} do
    {:ok, session} = UserSessions.create(user.id)
    assert :ok = Users.delete(user.id)
    assert :not_found = UserSessions.user_for_token(session.token)

    assert [[0]] ==
             Repo.query!("SELECT count(*) FROM user_sessions WHERE user_id = $1", [
               Ecto.UUID.dump!(user.id)
             ]).rows
  end

  test "user IDs, database hashes and malformed credentials are not bearer tokens", %{user: user} do
    {:ok, session} = UserSessions.create(user.id)
    hash = :crypto.hash(:sha256, session.token)

    for token <- [
          user.id,
          hash,
          Base.url_encode64(hash, padding: false),
          nil,
          %{},
          [],
          42,
          "",
          String.duplicate("!", 43),
          String.duplicate("a", 10_000),
          session.token <> "=",
          String.duplicate("A", 43)
        ] do
      assert :not_found = UserSessions.user_for_token(token)
      assert :ok = UserSessions.revoke(token)
    end

    assert {:ok, ^user} = UserSessions.user_for_token(session.token)
  end

  test "unknown and malformed user IDs cannot create sessions" do
    for id <- [Ecto.UUID.generate(), "invalid", nil, %{}, 42] do
      assert {:error, :user_not_found} = UserSessions.create(id)
      assert :ok = UserSessions.revoke_all(id)
    end
  end

  test "session issuance participates in the caller's transaction", %{user: user} do
    assert {:error, token} =
             Repo.transaction(fn ->
               {:ok, session} = UserSessions.create(user.id)
               assert {:ok, ^user} = UserSessions.user_for_token(session.token)
               Repo.rollback(session.token)
             end)

    assert :not_found = UserSessions.user_for_token(token)
  end

  test "PostgreSQL enforces hash size, uniqueness, expiry and user reference", %{user: user} do
    {:ok, session} = UserSessions.create(user.id)
    hash = :crypto.hash(:sha256, session.token)
    db_id = Ecto.UUID.dump!(user.id)
    created_at = ~N[2026-10-13 00:00:00.000000]
    expires_at = ~N[2026-10-14 00:00:00.000000]

    for {params, code} <- [
          {[hash, db_id, created_at, expires_at], :unique_violation},
          {[<<0>>, db_id, created_at, expires_at], :check_violation},
          {[:crypto.strong_rand_bytes(32), db_id, created_at, created_at], :check_violation},
          {[
             :crypto.strong_rand_bytes(32),
             Ecto.UUID.dump!(Ecto.UUID.generate()),
             created_at,
             expires_at
           ], :foreign_key_violation}
        ] do
      assert {:error, %Postgrex.Error{postgres: %{code: ^code}}} =
               Repo.query(
                 "INSERT INTO user_sessions (token_hash, user_id, created_at, expires_at) VALUES ($1, $2, $3, $4)",
                 params,
                 log: false
               )
    end
  end

  test "concurrent issuance creates independent revocable credentials", %{user: user} do
    sessions =
      1..8
      |> Task.async_stream(fn _ -> UserSessions.create(user.id) end, max_concurrency: 8)
      |> Enum.map(fn {:ok, {:ok, session}} -> session end)

    assert sessions |> Enum.map(& &1.token) |> Enum.uniq() |> length() == 8
    assert :ok = UserSessions.revoke_all(user.id)
    for session <- sessions, do: assert(:not_found == UserSessions.user_for_token(session.token))
  end
end
