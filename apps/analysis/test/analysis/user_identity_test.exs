defmodule Analysis.UserIdentityTest do
  use ExUnit.Case, async: false

  alias Analysis.Accounts
  alias Analysis.Analysis, as: AnalysisModel
  alias Analysis.AnalysisStore
  alias Analysis.UserLibrary
  alias Analysis.Users
  alias OpenChessLab.Repo

  setup do
    assert {:ok, first} = Users.create()
    assert {:ok, second} = Users.create()

    analysis_id = "library-" <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
    assert {:ok, 1} = AnalysisStore.insert(AnalysisModel.new(analysis_id, 42))

    on_exit(fn ->
      Users.delete(first.id)
      Users.delete(second.id)
      Repo.query!("DELETE FROM analyses WHERE analysis_id = $1", [analysis_id])
    end)

    %{first: first, second: second, analysis_id: analysis_id}
  end

  test "users have opaque UUIDs without personal fields", %{first: first, second: second} do
    assert {:ok, ^first} = Users.get(first.id)
    refute first.id == second.id
    assert {:ok, _} = Ecto.UUID.cast(first.id)
    assert Map.keys(first) |> Enum.sort() == [:created_at, :id]
    assert :not_found = Users.get("not-a-uuid")

    [[columns]] =
      Repo.query!(
        "SELECT array_agg(column_name ORDER BY column_name) FROM information_schema.columns WHERE table_name = 'users' AND table_schema = current_schema()",
        []
      ).rows

    assert columns == ["created_at", "id"]
  end

  test "multiple providers can link to one user and identify it", %{first: first} do
    assert {:ok, lichess_id} = Accounts.link_verified(first.id, "lichess", "lichess-sub-17")
    assert {:ok, ^lichess_id} = Accounts.link_verified(first.id, "lichess", "lichess-sub-17")
    assert {:ok, _github_id} = Accounts.link_verified(first.id, "github", "github-sub-17")

    assert Accounts.providers_for(first.id) == ["github", "lichess"]
    assert {:ok, first.id} == Accounts.user_for_verified_identity("lichess", "lichess-sub-17")
    assert :not_found == Accounts.user_for_verified_identity("lichess", "no-such-subject")
    assert :not_found == Accounts.user_for_verified_identity("github", "lichess-sub-17")
  end

  test "one external account cannot be claimed by another user", %{first: first, second: second} do
    assert {:ok, _id} = Accounts.link_verified(first.id, "lichess", "unique-subject")

    assert {:error, :already_linked} =
             Accounts.link_verified(second.id, "lichess", "unique-subject")

    assert {:ok, first.id} == Accounts.user_for_verified_identity("lichess", "unique-subject")
  end

  test "provider subjects are never stored in plaintext", %{first: first} do
    subject = "raw-private-provider-subject-123"
    assert {:ok, _id} = Accounts.link_verified(first.id, "lichess", subject)

    [[provider, digest, digest_size]] =
      Repo.query!(
        "SELECT provider, subject_hmac, octet_length(subject_hmac) FROM accounts WHERE user_id = $1",
        [Ecto.UUID.dump!(first.id)]
      ).rows

    assert provider == "lichess"
    assert digest_size == 32
    refute digest == subject
    assert :binary.match(digest, subject) == :nomatch
  end

  test "invalid account subjects and missing users are rejected", %{first: first} do
    assert {:error, :invalid_identity} = Accounts.link_verified(first.id, "LICHESS", "subject")
    assert {:error, :invalid_identity} = Accounts.link_verified(first.id, "lichess", "")
    assert {:error, :invalid_identity} = Accounts.link_verified("not-uuid", "lichess", "123")

    assert {:error, :user_not_found} =
             Accounts.link_verified(Ecto.UUID.generate(), "lichess", "123")
  end

  test "users may save the same analysis without duplicating it", context do
    assert :ok = UserLibrary.save(context.first.id, context.analysis_id)
    assert :ok = UserLibrary.save(context.first.id, context.analysis_id)
    assert :ok = UserLibrary.save(context.second.id, context.analysis_id)

    assert UserLibrary.list(context.first.id) == [context.analysis_id]
    assert UserLibrary.list(context.second.id) == [context.analysis_id]

    assert :ok = UserLibrary.remove(context.first.id, context.analysis_id)
    assert :not_found = UserLibrary.remove(context.first.id, context.analysis_id)
    assert UserLibrary.list(context.first.id) == []
    assert UserLibrary.list(context.second.id) == [context.analysis_id]
    assert {:ok, _analysis, _revision} = AnalysisStore.get(context.analysis_id)
  end

  test "a library cannot reference unknown users or analyses", context do
    assert {:error, :invalid_identity} = UserLibrary.save("invalid-uuid", context.analysis_id)
    assert {:error, :user_not_found} = UserLibrary.save(Ecto.UUID.generate(), context.analysis_id)
    assert {:error, :analysis_not_found} = UserLibrary.save(context.first.id, "absent-analysis")
  end

  test "library pages are bounded, scoped and continue after a removed cursor", context do
    ids =
      for n <- 1..51,
          do: "page-#{context.analysis_id}-#{String.pad_leading(to_string(n), 3, "0")}"

    on_exit(fn ->
      for id <- ids, do: AnalysisStore.delete(id, 1)
    end)

    for id <- ids do
      {:ok, 1} = AnalysisStore.insert(AnalysisModel.new(id, 42))
      :ok = UserLibrary.save(context.first.id, id)
    end

    :ok = UserLibrary.save(context.second.id, context.analysis_id)
    first = UserLibrary.page(context.first.id)
    assert Enum.map(first.entries, & &1.id) == Enum.take(ids, 50)
    assert first.next_cursor == Enum.at(ids, 49)
    assert Enum.all?(first.entries, &match?(%NaiveDateTime{}, &1.saved_at))
    :ok = UserLibrary.remove(context.first.id, first.next_cursor)
    last = UserLibrary.page(context.first.id, first.next_cursor)
    assert Enum.map(last.entries, & &1.id) == [List.last(ids)]
    assert last.next_cursor == nil
    assert UserLibrary.page("invalid") == %{entries: [], next_cursor: nil}
    assert UserLibrary.page(context.first.id, %{}) == %{entries: [], next_cursor: nil}

    assert UserLibrary.page(context.second.id).entries |> Enum.map(& &1.id) == [
             context.analysis_id
           ]
  end

  test "deleting a user clears account and library links but not the analysis", context do
    assert {:ok, _id} = Accounts.link_verified(context.first.id, "lichess", "delete-me")
    assert :ok = UserLibrary.save(context.first.id, context.analysis_id)
    assert :ok = Users.delete(context.first.id)

    assert :not_found = Users.get(context.first.id)
    assert Accounts.user_for_verified_identity("lichess", "delete-me") == :not_found
    assert UserLibrary.list(context.first.id) == []
    assert {:ok, _analysis, 1} = AnalysisStore.get(context.analysis_id)
  end

  test "deleting an analysis clears its saved references", context do
    assert :ok = UserLibrary.save(context.first.id, context.analysis_id)
    Repo.query!("DELETE FROM analyses WHERE analysis_id = $1", [context.analysis_id])
    assert UserLibrary.list(context.first.id) == []
  end
end
