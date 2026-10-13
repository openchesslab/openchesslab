defmodule Analysis.AccountResolutionTest do
  use ExUnit.Case, async: false

  alias Analysis.Accounts
  alias Analysis.Users
  alias Analysis.UserSessions
  alias OpenChessLab.Repo

  setup do
    before_ids = user_ids()
    on_exit(fn -> Enum.each(user_ids() -- before_ids, &Users.delete/1) end)
    %{before_ids: before_ids}
  end

  test "first login creates only a UUID user and an HMAC account; retries reuse both", context do
    subject = "private-verified-subject"
    assert {:ok, user_id} = Accounts.resolve_verified("lichess", subject)
    assert {:ok, %{id: ^user_id}} = Users.get(user_id)
    assert {:ok, ^user_id} = Accounts.resolve_verified("lichess", subject)
    assert {:ok, ^user_id} = Accounts.user_for_verified_identity("lichess", subject)
    assert user_ids() -- context.before_ids == [user_id]

    [[provider, digest]] =
      Repo.query!("SELECT provider, subject_hmac FROM accounts WHERE user_id = $1", [
        Ecto.UUID.dump!(user_id)
      ]).rows

    assert provider == "lichess"
    key = Application.fetch_env!(:analysis, :account_subject_hmac_key)
    assert digest == :crypto.mac(:hmac, :sha256, key, "lichess" <> <<0>> <> subject)
    refute digest == subject
  end

  test "prelinked accounts resolve to their owner without creating or merging users", context do
    {:ok, owner} = Users.create()
    {:ok, unrelated} = Users.create()
    {:ok, account_id} = Accounts.link_verified(owner.id, "lichess", "linked-subject")
    assert {:ok, owner.id} == Accounts.resolve_verified("lichess", "linked-subject")
    assert {:ok, ^account_id} = Accounts.link_verified(owner.id, "lichess", "linked-subject")

    assert {:error, :already_linked} =
             Accounts.link_verified(unrelated.id, "lichess", "linked-subject")

    assert Enum.sort(user_ids() -- context.before_ids) == Enum.sort([owner.id, unrelated.id])
  end

  test "provider and exact subject remain distinct identities" do
    {:ok, first} = Accounts.resolve_verified("lichess", "ExactSubject")
    {:ok, second} = Accounts.resolve_verified("github", "ExactSubject")
    {:ok, third} = Accounts.resolve_verified("lichess", "exactsubject")
    assert length(Enum.uniq([first, second, third])) == 3
  end

  test "invalid identities cannot create users", context do
    for {provider, subject} <- [
          {nil, "id"},
          {"lichess", nil},
          {"LICHESS", "id"},
          {"", "id"},
          {"lichess", ""},
          {%{}, []}
        ] do
      assert {:error, :invalid_identity} = Accounts.resolve_verified(provider, subject)
    end

    assert user_ids() == context.before_ids
  end

  test "missing or invalid HMAC configuration fails before creating a user", context do
    key = Application.fetch_env!(:analysis, :account_subject_hmac_key)

    try do
      Application.delete_env(:analysis, :account_subject_hmac_key)
      assert_raise ArgumentError, fn -> Accounts.resolve_verified("lichess", "subject") end
      Application.put_env(:analysis, :account_subject_hmac_key, "too-short")
      assert_raise ArgumentError, fn -> Accounts.resolve_verified("lichess", "subject") end
    after
      Application.put_env(:analysis, :account_subject_hmac_key, key)
    end

    assert user_ids() == context.before_ids
  end

  test "user, account and session participate in the caller's rollback", context do
    assert {:error, :later_failure} =
             Repo.transact(fn ->
               {:ok, user_id} = Accounts.resolve_verified("lichess", "rolled-back-subject")
               {:ok, session} = UserSessions.create(user_id)
               send(self(), {:issued, user_id, session.token})
               {:error, :later_failure}
             end)

    assert_receive {:issued, user_id, token}
    assert :not_found = Users.get(user_id)
    assert :not_found = Accounts.user_for_verified_identity("lichess", "rolled-back-subject")
    assert :not_found = UserSessions.user_for_token(token)
    assert user_ids() == context.before_ids
  end

  test "overlapping first logins converge without orphan users", context do
    results =
      overlap_writes(
        List.duplicate(fn -> Accounts.resolve_verified("lichess", "concurrent-subject") end, 8)
      )

    assert [{:ok, owner_id}] = Enum.uniq(results)
    assert user_ids() -- context.before_ids == [owner_id]
    assert Accounts.providers_for(owner_id) == ["lichess"]
  end

  test "a concurrent explicit link cannot be stolen by login resolution", context do
    {:ok, existing} = Users.create()

    [resolved, linked] =
      overlap_writes([
        fn -> Accounts.resolve_verified("lichess", "link-race") end,
        fn -> Accounts.link_verified(existing.id, "lichess", "link-race") end
      ])

    assert {:ok, owner_id} = resolved
    assert {:ok, ^owner_id} = Accounts.user_for_verified_identity("lichess", "link-race")

    if owner_id == existing.id do
      assert {:ok, _account_id} = linked
      assert user_ids() -- context.before_ids == [existing.id]
    else
      assert linked == {:error, :already_linked}
      assert Enum.sort(user_ids() -- context.before_ids) == Enum.sort([existing.id, owner_id])
    end
  end

  # Hold a SHARE table lock: lookups proceed, but every account INSERT waits.
  # Observe PostgreSQL's blocked writers before releasing, rather than relying
  # on task scheduling or a fixed sleep to exercise the conflicting inserts.
  defp overlap_writes(functions) do
    parent = self()

    locker =
      Task.async(fn ->
        Repo.transact(fn ->
          Repo.query!("LOCK TABLE accounts IN SHARE MODE", [])
          send(parent, :accounts_locked)

          receive do
            :release -> {:ok, :released}
          after
            5_000 -> {:error, :lock_timeout}
          end
        end)
      end)

    assert_receive :accounts_locked, 1_000
    tasks = Enum.map(functions, &Task.async/1)

    try do
      wait_for_writers(length(tasks), System.monotonic_time(:millisecond) + 3_000)
    after
      send(locker.pid, :release)
    end

    assert {:ok, :released} = Task.await(locker)
    Task.await_many(tasks)
  end

  defp wait_for_writers(expected, deadline) do
    [[waiting]] =
      Repo.query!(
        "SELECT count(*) FROM pg_locks WHERE locktype = 'relation' AND relation = 'accounts'::regclass AND mode = 'RowExclusiveLock' AND NOT granted",
        []
      ).rows

    if waiting == expected do
      :ok
    else
      assert System.monotonic_time(:millisecond) < deadline, "account writers did not overlap"
      Process.sleep(10)
      wait_for_writers(expected, deadline)
    end
  end

  defp user_ids do
    Repo.query!("SELECT id::text FROM users ORDER BY id", []).rows |> Enum.map(&hd/1)
  end
end
