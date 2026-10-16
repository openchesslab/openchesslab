defmodule Web.LichessSync do
  @moduledoc """
  Opt-in library sync for linked Lichess accounts. `Web.LichessSync.Worker`
  schedules it periodically; `kick/1` runs one user soon after they enable
  sync. Syncing pages a user's games forward from a stored `lastMoveAt`
  cursor, importing each into their library; a rejected grant is deleted and
  disabled honestly.
  """

  alias Analysis.{LibraryImport, ProviderGrants}
  alias Web.GameImport

  @page_size 50
  @max_pages_per_run 3

  @doc "Sync every grant with sync enabled; failures stay isolated per user."
  @spec sync_all() :: :ok
  def sync_all do
    "lichess"
    |> ProviderGrants.list_sync_enabled()
    |> Enum.each(&sync_user(&1.user_id))
  end

  @doc """
  Sync one user's library if their grant has sync enabled. Returns the number
  of games imported this run.
  """
  @spec sync_user(String.t()) :: {:ok, non_neg_integer()} | {:error, atom()}
  def sync_user(user_id) do
    with {:ok, token} <- ProviderGrants.get_token(user_id, "lichess"),
         {:ok, %{enabled: true, cursor: cursor}} <- ProviderGrants.sync_state(user_id, "lichess"),
         {:ok, username} <- GameImport.fetch_lichess_account_username(token),
         {:ok, imported} <- sync_pages(user_id, username, cursor) do
      {:ok, imported}
    else
      :not_found -> {:error, :no_grant}
      # Sync is opt-in; a grant without the flag is not an error.
      {:ok, %{enabled: false}} -> {:error, :sync_disabled}
      {:error, :unauthorized} -> disable_dead_grant(user_id)
      {:error, reason} -> {:error, reason}
    end
  end

  defp disable_dead_grant(user_id) do
    :ok = ProviderGrants.set_sync_enabled(user_id, "lichess", false)
    :ok = ProviderGrants.delete(user_id, "lichess")
    {:error, :unauthorized}
  end

  defp sync_pages(user_id, username, cursor, page \\ 1, imported \\ 0) do
    case GameImport.fetch_lichess_games_since(username, cursor, @page_size) do
      {:ok, []} ->
        {:ok, imported}

      {:ok, games} ->
        result =
          LibraryImport.import_games(user_id, Enum.map(games, &Map.take(&1, [:pgn, :title])))

        :ok = ProviderGrants.advance_cursor(user_id, "lichess", List.last(games).last_move_at + 1)
        imported = imported + length(result.imported)

        if length(games) == @page_size and page < @max_pages_per_run do
          sync_pages(user_id, username, List.last(games).last_move_at + 1, page + 1, imported)
        else
          {:ok, imported}
        end

      {:error, :rate_limited} ->
        # Leave the cursor where it is; the next run retries.
        {:ok, imported}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
