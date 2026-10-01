defmodule OpenChessLab.Repo do
  @moduledoc """
  Shared PostgreSQL repository for persistent OpenChessLab data.

  Domain-specific persistence remains owned by the domain applications.
  The shared repository owns the PostgreSQL connection pool and migration
  history used by those domain repositories.
  """

  use Ecto.Repo,
    otp_app: :database,
    adapter: Ecto.Adapters.Postgres
end
