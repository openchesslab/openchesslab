defmodule Web.OAuthAttemptsTest do
  use ExUnit.Case, async: false

  alias OpenChessLab.Repo
  alias Web.OAuthAttempts, as: Attempts

  setup do
    on_exit(fn -> Repo.query!("DELETE FROM oauth_attempts", []) end)
    :ok
  end

  test "independent random state and verifier produce the documented S256 challenge" do
    {:ok, attempt} = Attempts.create()
    {:ok, other} = Attempts.create()
    params = attempt.authorization_params
    state = params["state"]

    assert Map.keys(params) |> Enum.sort() == ["code_challenge", "code_challenge_method", "state"]
    assert params["code_challenge_method"] == "S256"
    refute state == other.authorization_params["state"]
    refute attempt.browser_token == other.browser_token
    assert {:ok, raw_state} = Base.url_decode64(state, padding: false)
    assert byte_size(raw_state) == 32

    assert {:ok, verifier} = Attempts.consume(state, attempt.browser_token)
    assert verifier =~ ~r/\A[A-Za-z0-9_-]{43}\z/
    refute verifier == state
    refute attempt.browser_token =~ verifier

    assert params["code_challenge"] ==
             Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false)

    assert {:error, :invalid_attempt} = Attempts.consume(state, attempt.browser_token)
  end

  test "PostgreSQL contains only hashes and a five-minute lifetime" do
    {:ok, attempt} = Attempts.create()

    assert [[state_hash, browser_hash, created_at, expires_at]] =
             Repo.query!(
               "SELECT state_hash, browser_token_hash, created_at, expires_at FROM oauth_attempts",
               []
             ).rows

    assert state_hash == :crypto.hash(:sha256, attempt.authorization_params["state"])
    assert browser_hash == :crypto.hash(:sha256, attempt.browser_token)
    assert expires_at == attempt.expires_at
    assert NaiveDateTime.diff(expires_at, created_at) == 300

    [[columns]] =
      Repo.query!(
        "SELECT array_agg(column_name ORDER BY column_name) FROM information_schema.columns WHERE table_name = 'oauth_attempts' AND table_schema = current_schema()",
        []
      ).rows

    assert columns == ["browser_token_hash", "created_at", "expires_at", "state_hash"]
  end

  test "another browser, public state, tampering and database hashes cannot consume the attempt" do
    {:ok, first} = Attempts.create()
    {:ok, second} = Attempts.create()
    state = first.authorization_params["state"]
    other_state = second.authorization_params["state"]

    for {callback_state, token} <- [
          {state, second.browser_token},
          {other_state, first.browser_token},
          {state, state},
          {state, first.browser_token <> "tampered"},
          {state, :crypto.hash(:sha256, first.browser_token)},
          {Base.url_encode64(:crypto.hash(:sha256, state), padding: false), first.browser_token}
        ] do
      assert {:error, :invalid_attempt} = Attempts.consume(callback_state, token)
    end

    assert {:ok, _} = Attempts.consume(state, first.browser_token)
    assert {:ok, _} = Attempts.consume(other_state, second.browser_token)
  end

  test "malformed or missing callback values fail closed without consuming a valid attempt" do
    {:ok, attempt} = Attempts.create()
    state = attempt.authorization_params["state"]

    for value <- [
          nil,
          %{},
          [],
          42,
          "",
          <<255>>,
          String.duplicate("!", 43),
          String.duplicate("a", 10_000)
        ] do
      assert {:error, :invalid_attempt} = Attempts.consume(value, attempt.browser_token)
      assert {:error, :invalid_attempt} = Attempts.consume(state, value)
    end

    assert {:ok, _} = Attempts.consume(state, attempt.browser_token)
  end

  test "database expiry rejects and deletes the bound attempt without sleeps" do
    {:ok, attempt} = Attempts.create()
    expire_all()

    assert {:error, :invalid_attempt} =
             Attempts.consume(attempt.authorization_params["state"], attempt.browser_token)

    assert count() == 0
  end

  test "encrypted browser token has its own expiry and purpose binding" do
    for {salt, signed_at} <- [
          {"oauth-attempt", System.system_time(:second) - 301},
          {"another-purpose", System.system_time(:second)}
        ] do
      {:ok, attempt} = Attempts.create()

      token =
        Phoenix.Token.encrypt(
          Web.Endpoint,
          salt,
          {String.duplicate("A", 43), %{provider: "lichess", intent: :login}},
          signed_at: signed_at
        )

      # Match the DB hash deliberately, so this tests decryption rather than hash mismatch.
      Repo.query!(
        "UPDATE oauth_attempts SET browser_token_hash = $1 WHERE state_hash = $2",
        [
          :crypto.hash(:sha256, token),
          :crypto.hash(:sha256, attempt.authorization_params["state"])
        ]
      )

      assert {:error, :invalid_attempt} =
               Attempts.consume(attempt.authorization_params["state"], token)
    end
  end

  test "a valid provider denial consumes the attempt permanently" do
    {:ok, attempt} = Attempts.create()
    state = attempt.authorization_params["state"]
    assert {:error, :invalid_attempt} = Attempts.cancel(state, nil)
    assert :ok = Attempts.cancel(state, attempt.browser_token)
    assert {:error, :invalid_attempt} = Attempts.consume(state, attempt.browser_token)
    assert {:error, :invalid_attempt} = Attempts.cancel(state, attempt.browser_token)
  end

  test "exactly one concurrent callback receives the verifier" do
    {:ok, attempt} = Attempts.create()
    parent = self()

    tasks =
      for _ <- 1..8 do
        Task.async(fn ->
          send(parent, {:ready, self()})

          receive do
            :consume ->
              Attempts.consume(attempt.authorization_params["state"], attempt.browser_token)
          end
        end)
      end

    for task <- tasks do
      pid = task.pid
      assert_receive {:ready, ^pid}, 1_000
    end

    for task <- tasks, do: send(task.pid, :consume)
    results = Task.await_many(tasks)
    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :invalid_attempt})) == 7
    assert count() == 0
  end

  test "later login rollback cannot restore a consumed attempt" do
    {:ok, attempt} = Attempts.create()
    state = attempt.authorization_params["state"]

    for operation <- [&Attempts.consume/2, &Attempts.cancel/2] do
      assert_raise ArgumentError, "OAuth attempts must be consumed outside a transaction", fn ->
        Repo.transaction(fn -> operation.(state, attempt.browser_token) end)
      end
    end

    assert {:ok, _} = Attempts.consume(state, attempt.browser_token)

    assert {:error, :exchange_failed} =
             Repo.transaction(fn -> Repo.rollback(:exchange_failed) end)

    assert {:error, :invalid_attempt} = Attempts.consume(state, attempt.browser_token)
  end

  test "creation prunes expired attempts while keeping live attempts" do
    {:ok, expired} = Attempts.create()
    expire_all()
    {:ok, live} = Attempts.create()
    assert count() == 1
    assert Attempts.prune_expired() == 0

    assert {:error, :invalid_attempt} =
             Attempts.consume(expired.authorization_params["state"], expired.browser_token)

    assert {:ok, _} = Attempts.consume(live.authorization_params["state"], live.browser_token)
  end

  test "cleanup is bounded and preserves unexpired attempts" do
    {:ok, live} = Attempts.create()

    Repo.query!(
      """
      INSERT INTO oauth_attempts (state_hash, browser_token_hash, created_at, expires_at)
      SELECT decode(lpad(to_hex(n), 64, '0'), 'hex'), decode(repeat('00', 32), 'hex'),
             timezone('UTC', statement_timestamp()) - interval '10 minutes',
             timezone('UTC', statement_timestamp()) - interval '5 minutes'
      FROM generate_series(1, 1002) AS n
      """,
      []
    )

    assert Attempts.prune_expired() == 1000
    assert count() == 3
    assert Attempts.prune_expired() == 2
    assert count() == 1
    assert {:ok, _} = Attempts.consume(live.authorization_params["state"], live.browser_token)
  end

  test "database constraints reject malformed hashes, duplicate state and invalid expiry" do
    {:ok, attempt} = Attempts.create()
    state_hash = :crypto.hash(:sha256, attempt.authorization_params["state"])
    browser_hash = :crypto.hash(:sha256, attempt.browser_token)
    start = ~N[2026-10-13 00:00:00.000000]
    finish = ~N[2026-10-13 00:05:00.000000]

    sql = """
    INSERT INTO oauth_attempts (state_hash, browser_token_hash, created_at, expires_at)
    VALUES ($1, $2, $3, $4)
    """

    for {params, code} <- [
          {[state_hash, browser_hash, start, finish], :unique_violation},
          {[<<0>>, browser_hash, start, finish], :check_violation},
          {[:crypto.strong_rand_bytes(32), <<0>>, start, finish], :check_violation},
          {[:crypto.strong_rand_bytes(32), browser_hash, start, start], :check_violation}
        ] do
      assert {:error, %Postgrex.Error{postgres: %{code: ^code}}} =
               Repo.query(sql, params, log: false)
    end
  end

  defp expire_all do
    Repo.query!(
      "UPDATE oauth_attempts SET created_at = timezone('UTC', statement_timestamp()) - interval '10 minutes', expires_at = timezone('UTC', statement_timestamp()) - interval '1 second'",
      []
    )
  end

  defp count do
    [[count]] = Repo.query!("SELECT count(*) FROM oauth_attempts", []).rows
    count
  end
end
