defmodule Analysis.UserSessionPrunerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Analysis.Users
  alias Analysis.UserSessionPruner
  alias Analysis.UserSessions
  alias OpenChessLab.Repo

  setup do
    {:ok, user} = Users.create()
    on_exit(fn -> Users.delete(user.id) end)
    %{user: user}
  end

  test "a pass is bounded, preserves active sessions and can drain the remainder", %{user: user} do
    expired(user.id, 1005)
    {:ok, active} = UserSessions.create(user.id)
    assert UserSessions.prune_expired() == 1000
    assert count(user.id) == 6
    assert {:ok, ^user} = UserSessions.user_for_token(active.token)
    assert UserSessions.prune_expired() == 5
    assert UserSessions.prune_expired() == 0
    assert count(user.id) == 1
    assert {:ok, ^user} = Users.get(user.id)
  end

  test "locked expired sessions are skipped and removed in a later pass", %{user: user} do
    [locked | _rest] = expired(user.id, 3)
    parent = self()

    holder =
      Task.async(fn ->
        Repo.transact(fn ->
          Repo.query!(
            "SELECT token_hash FROM user_sessions WHERE token_hash = $1 FOR UPDATE",
            [locked],
            log: false
          )

          send(parent, :locked)

          receive do
            :release -> {:ok, :released}
          after
            5_000 -> {:error, :lock_timeout}
          end
        end)
      end)

    try do
      assert_receive :locked, 1_000
      assert UserSessions.prune_expired() == 2
      assert count(user.id) == 1
    after
      send(holder.pid, :release)
    end

    assert {:ok, :released} = Task.await(holder)
    assert UserSessions.prune_expired() == 1
    assert count(user.id) == 0
  end

  test "concurrent passes account for each deleted row only once", %{user: user} do
    expired(user.id, 2010)
    {:ok, active} = UserSessions.create(user.id)

    counts =
      1..4
      |> Task.async_stream(fn _ -> UserSessions.prune_expired() end, max_concurrency: 4)
      |> Enum.map(fn {:ok, count} -> count end)

    assert Enum.all?(counts, &(&1 in 0..1000))
    assert Enum.sum(counts) == 2010
    assert count(user.id) == 1
    assert {:ok, ^user} = UserSessions.user_for_token(active.token)
  end

  test "scheduled passes prune expired sessions and replace the previous timer", %{user: user} do
    expired(user.id, 2)
    {:ok, active} = UserSessions.create(user.id)
    worker = start_supervised!({UserSessionPruner, initial_delay_ms: to_timeout(hour: 1)})
    before = :sys.get_state(worker)
    send(worker, :prune)
    after_pass = :sys.get_state(worker)
    assert count(user.id) == 1
    assert {:ok, ^user} = UserSessions.user_for_token(active.token)
    assert Process.read_timer(before.timer) == false
    assert is_integer(Process.read_timer(after_pass.timer))

    send(worker, :prune)
    next_pass = :sys.get_state(worker)
    assert Process.read_timer(after_pass.timer) == false
    assert is_integer(Process.read_timer(next_pass.timer))
    assert Process.alive?(worker)
  end

  test "a database failure is sanitized and the next scheduled pass still works", %{user: user} do
    expired(user.id, 1)
    worker = start_supervised!({UserSessionPruner, initial_delay_ms: to_timeout(hour: 1)})
    Repo.query!("ALTER TABLE user_sessions RENAME TO user_sessions_pruner_test", [])

    try do
      log =
        capture_log(fn ->
          send(worker, :prune)
          state = :sys.get_state(worker)
          assert Process.alive?(worker)
          assert is_integer(Process.read_timer(state.timer))
        end)

      assert log =~ "User session pruning failed"
      refute log =~ "undefined_table"
      refute log =~ "token_hash"
    after
      Repo.query!("ALTER TABLE user_sessions_pruner_test RENAME TO user_sessions", [])
    end

    send(worker, :prune)
    :sys.get_state(worker)
    assert count(user.id) == 0
  end

  test "production enables the supervised worker; local test configuration does not" do
    refute Analysis.UserSessionPruner in Analysis.Application.children()
    prior = Application.fetch_env(:analysis, :user_session_pruning_enabled)

    try do
      Application.put_env(:analysis, :user_session_pruning_enabled, true)
      assert Analysis.UserSessionPruner in Analysis.Application.children()
      path = Path.expand("../../../../config/prod.exs", __DIR__)

      assert Config.Reader.read!(path, env: :prod, target: :host)[:analysis][
               :user_session_pruning_enabled
             ]
    after
      case prior do
        {:ok, value} -> Application.put_env(:analysis, :user_session_pruning_enabled, value)
        :error -> Application.delete_env(:analysis, :user_session_pruning_enabled)
      end
    end
  end

  test "the migration supplies an index matching the expiry scan order" do
    assert [[definition]] =
             Repo.query!(
               "SELECT indexdef FROM pg_indexes WHERE schemaname = current_schema() AND tablename = 'user_sessions' AND indexname = 'user_sessions_expires_at_token_hash_index'",
               []
             ).rows

    assert definition =~ "USING btree (expires_at, token_hash)"
  end

  defp expired(user_id, count) do
    hashes = for _ <- 1..count, do: :crypto.strong_rand_bytes(32)

    sql = """
    INSERT INTO user_sessions (token_hash, user_id, created_at, expires_at)
    SELECT hash, $2, timezone('UTC', statement_timestamp()) - interval '2 days',
           timezone('UTC', statement_timestamp()) - interval '1 hour'
    FROM unnest($1::bytea[]) AS hash
    """

    Repo.query!(sql, [hashes, Ecto.UUID.dump!(user_id)], log: false)

    hashes
  end

  defp count(user_id) do
    [[count]] =
      Repo.query!("SELECT count(*) FROM user_sessions WHERE user_id = $1", [
        Ecto.UUID.dump!(user_id)
      ]).rows

    count
  end
end
