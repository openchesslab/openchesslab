defmodule OpenChessLab.Database.Migrations do
  @moduledoc """
  The migration versions this release expects, computed at compile time so
  the readiness check works without the migrations directory on disk
  (releases bundle no .exs files).
  """

  @expected_versions Path.wildcard(Path.join(__DIR__, "../../priv/repo/migrations/*.exs"))
                     |> Enum.map(fn path ->
                       path
                       |> Path.basename(".exs")
                       |> String.split("_", parts: 2)
                       |> hd()
                       |> String.to_integer()
                     end)

  @doc "Sorted migration versions the release expects to be applied."
  @spec expected_versions() :: [non_neg_integer()]
  def expected_versions, do: @expected_versions

  @doc """
  The expected versions missing from `schema_migrations` (the database is
  behind this release). Empty list means migrations are current.
  """
  @spec missing() :: [non_neg_integer()]
  def missing do
    %{rows: [[applied]]} =
      OpenChessLab.Repo.query!("SELECT array_agg(version) FROM schema_migrations")

    applied = applied || []
    @expected_versions -- applied
  end
end
