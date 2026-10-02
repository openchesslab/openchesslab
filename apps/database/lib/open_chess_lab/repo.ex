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

  @spec ready?() :: boolean()
  def ready? do
    case query(
           "SELECT 1",
           []
         ) do
      {:ok, _result} ->
        true

      {:error, _reason} ->
        false
    end
  rescue
    _error ->
      false
  catch
    :exit, _reason ->
      false
  end
end
