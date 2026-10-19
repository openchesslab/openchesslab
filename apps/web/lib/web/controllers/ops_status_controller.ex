defmodule Web.OpsStatusController do
  @moduledoc """
  A small honest status snapshot for the ops surface: corpus size, feature
  digest coverage and live room counts. Large tables use PostgreSQL's
  estimate (`reltuples`) so the endpoint stays cheap; the exact record
  count is cheap at the current corpus size.
  """

  use Web, :controller

  alias Analysis.GameSearch
  alias OpenChessLab.Repo
  alias Web.NodeInfo

  def show(conn, _params) do
    json(conn, %{
      node: %{region: NodeInfo.region()},
      corpus: corpus(),
      features: features(),
      rooms: rooms()
    })
  end

  defp corpus do
    %{
      positions: estimate("positions"),
      canonical_games: estimate("games"),
      occurrences: estimate("game_occurrences"),
      records: GameSearch.corpus_size()
    }
  end

  defp features do
    digests = estimate("position_digests")
    positions = estimate("positions")

    %{
      atoms: exact_count("feature_atoms"),
      digests: digests,
      digest_coverage: if(positions > 0, do: Float.round(digests / positions, 3), else: 0.0)
    }
  end

  defp rooms do
    %{active: Horde.Registry.count(Analysis.RoomRegistry)}
  end

  defp exact_count(table) do
    %{rows: [[count]]} = Repo.query!("SELECT count(*) FROM #{table}")
    count
  end

  # PostgreSQL's planner estimate: good enough for large tables, free to read.
  defp estimate(table) do
    %{rows: [[estimate]]} =
      Repo.query!("SELECT reltuples::bigint FROM pg_class WHERE relname = $1", [table])

    estimate
  end
end
