defmodule Analysis.ProviderGrantsTest do
  use ExUnit.Case, async: false

  alias Analysis.ProviderGrants
  alias Analysis.Users
  alias OpenChessLab.Repo

  defp uuid(id) do
    {:ok, dumped} = Ecto.UUID.dump(id)
    dumped
  end

  setup do
    {:ok, user} = Users.create()
    on_exit(fn -> Users.delete(user.id) end)
    %{user: user}
  end

  test "a grant round-trips through encryption", %{user: user} do
    assert :ok = ProviderGrants.put(user.id, "lichess", "lip_test-token")
    assert {:ok, "lip_test-token"} = ProviderGrants.get_token(user.id, "lichess")

    # The stored row never contains the plaintext.
    [[blob]] =
      Repo.query!(
        "SELECT token_encrypted FROM provider_grants WHERE user_id = $1",
        [uuid(user.id)]
      ).rows

    refute blob =~ "lip_test-token"
  end

  test "one grant per provider: putting again overwrites", %{user: user} do
    assert :ok = ProviderGrants.put(user.id, "lichess", "first")
    assert :ok = ProviderGrants.put(user.id, "lichess", "second")
    assert {:ok, "second"} = ProviderGrants.get_token(user.id, "lichess")
  end

  test "missing grants read as not_found, delete is idempotent", %{user: user} do
    assert :not_found = ProviderGrants.get_token(user.id, "lichess")
    refute ProviderGrants.has?(user.id, "lichess")

    assert :ok = ProviderGrants.put(user.id, "lichess", "x")
    assert ProviderGrants.has?(user.id, "lichess")
    assert :ok = ProviderGrants.delete(user.id, "lichess")
    assert :ok = ProviderGrants.delete(user.id, "lichess")
    refute ProviderGrants.has?(user.id, "lichess")
  end

  test "a tampered grant reads as not_found rather than decrypting", %{user: user} do
    assert :ok = ProviderGrants.put(user.id, "lichess", "real-token")

    Repo.query!(
      "UPDATE provider_grants SET token_encrypted = $1 WHERE user_id = $2",
      [:crypto.strong_rand_bytes(40), uuid(user.id)]
    )

    assert :not_found = ProviderGrants.get_token(user.id, "lichess")
  end

  test "grants disappear with the user", %{user: user} do
    assert :ok = ProviderGrants.put(user.id, "lichess", "x")
    assert :ok = Users.delete(user.id)

    assert Repo.query!("SELECT 1 FROM provider_grants WHERE user_id = $1", [uuid(user.id)]).rows ==
             []
  end
end
