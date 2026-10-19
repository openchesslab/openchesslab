defmodule Web.AuthRuntimeConfigTest do
  use ExUnit.Case, async: false

  @runtime Path.expand("../../../../config/runtime.exs", __DIR__)
  @variables ~w(GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET GOOGLE_REDIRECT_URI ACCOUNT_SUBJECT_HMAC_KEY LICHESS_CLIENT_ID LICHESS_REDIRECT_URI SECRET_KEY_BASE DATABASE_URL DNS_CLUSTER_QUERY PORT POOL_SIZE OPS_USER OPS_PASSWORD)
  @key Base.encode64(String.duplicate("private-test-key", 3))

  setup do
    previous = Map.new(@variables, &{&1, System.get_env(&1)})
    Enum.each(@variables, &System.delete_env/1)

    System.put_env("SECRET_KEY_BASE", String.duplicate("endpoint-test-secret", 4))
    System.put_env("DATABASE_URL", "ecto://unused:unused@localhost/openchesslab_test")
    System.put_env("OPS_PASSWORD", "ops-test-password")

    on_exit(fn ->
      Enum.each(previous, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end)

    :ok
  end

  test "unconfigured authentication stays disabled without generating an identity key" do
    config = read(:prod)
    assert config[:web][:lichess_oauth] == nil
    assert config[:web][:google_oauth] == nil
    refute Keyword.has_key?(config[:analysis], :account_subject_hmac_key)
  end

  test "the ops surface requires a password in production" do
    System.delete_env("OPS_PASSWORD")

    assert_raise RuntimeError, ~r/OPS_PASSWORD/, fn -> read(:prod) end
  end

  test "Google can be enabled independently with a secret, stable HMAC key and HTTPS" do
    System.put_env("GOOGLE_CLIENT_ID", "google-test-client")
    System.put_env("GOOGLE_CLIENT_SECRET", "private-test-secret")
    System.put_env("GOOGLE_REDIRECT_URI", "https://example.org/auth/google/callback")

    assert_raise RuntimeError,
                 "ACCOUNT_SUBJECT_HMAC_KEY is required for production Google authentication",
                 fn -> read(:prod) end

    System.put_env("ACCOUNT_SUBJECT_HMAC_KEY", @key)
    config = read(:prod)
    assert config[:web][:google_oauth].client_id == "google-test-client"
    assert config[:web][:google_oauth].client_secret == "private-test-secret"
    assert config[:web][:lichess_oauth] == nil

    System.put_env("GOOGLE_REDIRECT_URI", "http://localhost:4000/auth/google/callback")

    assert_raise RuntimeError, "GOOGLE_REDIRECT_URI must use HTTPS in production", fn ->
      read(:prod)
    end

    assert read(:dev)[:web][:google_oauth].redirect_uri ==
             "http://localhost:4000/auth/google/callback"
  end

  test "partial or unsafe Google configuration fails without disclosing credentials" do
    for {key, value} <- [
          {"GOOGLE_CLIENT_ID", nil},
          {"GOOGLE_CLIENT_SECRET", nil},
          {"GOOGLE_REDIRECT_URI", nil},
          {"GOOGLE_CLIENT_SECRET", " "},
          {"GOOGLE_REDIRECT_URI", "http://remote.example/private-secret"}
        ] do
      System.put_env("GOOGLE_CLIENT_ID", "google-test-client")
      System.put_env("GOOGLE_CLIENT_SECRET", "private-test-secret")
      System.put_env("GOOGLE_REDIRECT_URI", "https://example.org/auth/google/callback")
      if value, do: System.put_env(key, value), else: System.delete_env(key)
      error = assert_raise RuntimeError, fn -> read(:prod) end

      assert error.message ==
               "GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET and GOOGLE_REDIRECT_URI must contain valid OAuth configuration"
    end
  end

  test "decodes a stable identity key without requiring OAuth configuration" do
    System.put_env("ACCOUNT_SUBJECT_HMAC_KEY", @key)
    assert read(:prod)[:analysis][:account_subject_hmac_key] == Base.decode64!(@key)
    assert read(:prod)[:analysis][:account_subject_hmac_key] == Base.decode64!(@key)

    minimum_key = String.duplicate("k", 32)
    System.put_env("ACCOUNT_SUBJECT_HMAC_KEY", Base.encode64(minimum_key))
    assert read(:prod)[:analysis][:account_subject_hmac_key] == minimum_key
  end

  test "rejects malformed and short secrets without disclosing their values" do
    for value <- ["private-invalid!", "", Base.encode64(String.duplicate("k", 31))] do
      System.put_env("ACCOUNT_SUBJECT_HMAC_KEY", value)
      error = assert_raise RuntimeError, fn -> read(:prod) end

      assert error.message ==
               "ACCOUNT_SUBJECT_HMAC_KEY must be standard Base64 encoding at least 32 bytes"
    end
  end

  test "complete production configuration loads the exact client ID and callback" do
    configure("https://openchesslab.example/auth/lichess/callback")
    System.put_env("ACCOUNT_SUBJECT_HMAC_KEY", @key)
    config = read(:prod)

    assert config[:web][:lichess_oauth] == %{
             client_id: "openchesslab.example",
             redirect_uri: "https://openchesslab.example/auth/lichess/callback"
           }

    assert config[:analysis][:account_subject_hmac_key] !=
             config[:web][Web.Endpoint][:secret_key_base]
  end

  test "production OAuth requires the identity key and HTTPS even on loopback" do
    configure("https://openchesslab.example/auth/lichess/callback")

    assert_raise RuntimeError,
                 "ACCOUNT_SUBJECT_HMAC_KEY is required for production Lichess authentication",
                 fn ->
                   read(:prod)
                 end

    System.put_env("ACCOUNT_SUBJECT_HMAC_KEY", @key)
    configure("http://localhost:4000/auth/lichess/callback")

    assert_raise RuntimeError, "LICHESS_REDIRECT_URI must use HTTPS in production", fn ->
      read(:prod)
    end
  end

  test "development permits loopback HTTP and retains its separately configured key" do
    configure("http://localhost:4000/auth/lichess/callback")
    config = read(:dev)

    assert config[:web][:lichess_oauth][:redirect_uri] ==
             "http://localhost:4000/auth/lichess/callback"

    refute Keyword.has_key?(config[:analysis], :account_subject_hmac_key)
  end

  test "partial OAuth configuration fails instead of silently disabling authentication" do
    for missing <- ["LICHESS_CLIENT_ID", "LICHESS_REDIRECT_URI"] do
      configure("https://openchesslab.example/auth/lichess/callback")
      System.delete_env(missing)
      assert_invalid()
    end
  end

  test "unsafe callback URLs and empty client IDs fail without exposing values" do
    for uri <- [
          "/callback",
          "http://remote.example/callback",
          "https://private:password@example.org/callback",
          "https://example.org/callback#secret"
        ] do
      configure(uri)
      assert_invalid()
    end

    configure("https://example.org/callback")
    System.put_env("LICHESS_CLIENT_ID", " ")
    assert_invalid()
  end

  defp configure(uri) do
    System.put_env("LICHESS_CLIENT_ID", "openchesslab.example")
    System.put_env("LICHESS_REDIRECT_URI", uri)
  end

  defp assert_invalid do
    assert_raise RuntimeError,
                 "LICHESS_CLIENT_ID and LICHESS_REDIRECT_URI must contain valid OAuth configuration",
                 fn ->
                   read(:prod)
                 end
  end

  # Reads the real release configuration without starting an app or connecting
  # to its configured database. Environment mutations are restored after tests.
  defp read(env), do: Config.Reader.read!(@runtime, env: env, target: :host)
end
