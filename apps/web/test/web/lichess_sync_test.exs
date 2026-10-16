defmodule Web.LichessSyncTest do
  use Web.ConnCase, async: false

  alias Analysis.{ProviderGrants, UserLibrary, Users}
  alias Web.LichessSync

  setup do
    original = Application.fetch_env(:web, :game_import_request)

    on_exit(fn ->
      case original do
        {:ok, value} -> Application.put_env(:web, :game_import_request, value)
        :error -> Application.delete_env(:web, :game_import_request)
      end
    end)

    {:ok, user} = Users.create()
    :ok = ProviderGrants.put(user.id, "lichess", "lip_test_token")
    on_exit(fn -> Users.delete(user.id) end)

    %{user: user}
  end

  test "sync imports new games into the library and advances the cursor", %{user: user} do
    :ok = ProviderGrants.set_sync_enabled(user.id, "lichess", true)

    # The corpus search test is keyset-paged; remove this test's records after.
    on_exit(fn ->
      OpenChessLab.Repo.query!(
        "DELETE FROM game_records WHERE metadata->>'event' IN ('A', 'B')",
        []
      )
    end)

    stub_games([
      %{
        "id" => "g1",
        "pgn" => "[Event \"A\"]\n\n1. e4 e5 2. Nf3 Nc6 *",
        "winner" => "white",
        "lastMoveAt" => 1_700_000_000_000,
        "players" => %{
          "white" => %{"user" => %{"name" => "Alpha"}},
          "black" => %{"user" => %{"name" => "Beta"}}
        }
      },
      %{
        "id" => "g2",
        "pgn" => "[Event \"B\"]\n\n1. d4 d5 *",
        "lastMoveAt" => 1_700_000_600_000,
        "players" => %{
          "white" => %{"user" => %{"name" => "Gamma"}},
          "black" => %{"user" => %{"name" => "Delta"}}
        }
      }
    ])

    assert {:ok, 2} = LichessSync.sync_user(user.id)

    titles = UserLibrary.page(user.id).entries |> Enum.map(& &1.title) |> Enum.sort()
    assert titles == ["Alpha – Beta 1-0 (2023)", "Gamma – Delta ½-½ (2023)"]

    assert {:ok, %{cursor: 1_700_000_600_001, synced_at: synced}} =
             ProviderGrants.sync_state(user.id, "lichess")

    refute is_nil(synced)

    # Nothing new: the second run imports nothing and creates no duplicates.
    stub_games([])
    assert {:ok, 0} = LichessSync.sync_user(user.id)
    assert length(UserLibrary.page(user.id).entries) == 2
  end

  test "a rejected grant disables sync and deletes the grant", %{user: user} do
    :ok = ProviderGrants.set_sync_enabled(user.id, "lichess", true)
    stub_requests([{401, ""}])

    assert {:error, :unauthorized} = LichessSync.sync_user(user.id)

    refute ProviderGrants.has?(user.id, "lichess")
    assert ProviderGrants.sync_state(user.id, "lichess") == :not_found
  end

  test "sync is opt-in: a grant without the flag never syncs", %{user: user} do
    assert {:error, :sync_disabled} = LichessSync.sync_user(user.id)
  end

  # One stubbed account lookup plus one game page per call.
  defp stub_games(games) do
    body = Enum.map_join(games, "\n", &Jason.encode!/1)
    stub_requests([{200, Jason.encode!(%{"username" => "tester"})}, {200, body}])
  end

  defp stub_requests(responses) do
    agent =
      start_supervised!(%{id: make_ref(), start: {Agent, :start_link, [fn -> responses end]}})

    request = fn _method, _payload, _http, _options ->
      Agent.get_and_update(agent, fn
        [{status, body} | rest] -> {{:ok, {{~c"HTTP/1.1", status, ~c""}, [], body}}, rest}
      end)
    end

    Application.put_env(:web, :game_import_request, request)
  end
end
