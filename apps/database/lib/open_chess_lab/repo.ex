defmodule OpenChessLab.Repo do
  @moduledoc """
  Shared PostgreSQL repository for persistent OpenChessLab data.

  Domain-specific persistence remains owned by the domain applications.
  `position_db` and `game_db` can depend on this repository through
  PostgreSQL-backed storage adapters without owning separate connection
  pools or migration histories.
  """

  use Ecto.Repo,
    otp_app: :database,
    adapter: Ecto.Adapters.Postgres
end
