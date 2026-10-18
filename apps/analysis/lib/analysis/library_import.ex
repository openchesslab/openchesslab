defmodule Analysis.LibraryImport do
  @moduledoc """
  Imports PGN games as annotated analyses into a user's library — used by the
  opt-in Lichess sync. Each game becomes a canonical game record plus an
  analysis plus a library entry titled "White – Black 1-0 (2026)". Games that
  fail to parse are counted as skipped, never partially imported.
  """

  alias Analysis.PgnAnalysisImporter
  alias OpenChessLab.Repo

  @spec import_games(String.t(), [%{pgn: String.t(), title: String.t()}]) ::
          %{imported: [String.t()], skipped: non_neg_integer()}
  def import_games(user_id, games) when is_binary(user_id) and is_list(games) do
    case Ecto.UUID.dump(user_id) do
      {:ok, db_user} ->
        games
        |> Enum.reduce(%{imported: [], skipped: 0}, fn game, acc ->
          case import_one(db_user, game) do
            {:ok, analysis_id} -> %{acc | imported: [analysis_id | acc.imported]}
            {:error, _reason} -> %{acc | skipped: acc.skipped + 1}
          end
        end)
        |> then(fn acc -> %{acc | imported: Enum.reverse(acc.imported)} end)

      :error ->
        %{imported: [], skipped: length(games)}
    end
  end

  defp import_one(db_user, %{pgn: pgn, title: title}) do
    analysis_id = new_id("analysis")
    record_id = new_id("game-record")

    Repo.transaction(fn ->
      case PgnAnalysisImporter.import(analysis_id, record_id, pgn, source: "lichess") do
        {:ok, _analysis, _revision} ->
          Repo.query!(
            "INSERT INTO user_analyses (user_id, analysis_id, title) VALUES ($1, $2, $3) ON CONFLICT (user_id, analysis_id) DO NOTHING",
            [db_user, analysis_id, title],
            log: false
          )

          analysis_id

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, analysis_id} -> {:ok, analysis_id}
      {:error, reason} -> {:error, reason}
    end
  end

  defp new_id(prefix),
    do: prefix <> "-" <> Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
end
