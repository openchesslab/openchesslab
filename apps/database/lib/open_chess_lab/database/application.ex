defmodule OpenChessLab.Database.Application do
  @moduledoc false

  use Application

  alias OpenChessLab.Repo

  @impl true
  def start(_type, _args) do
    Supervisor.start_link(
      children(),
      strategy: :one_for_one,
      name: OpenChessLab.Database.Supervisor
    )
  end

  @doc false
  def children do
    if Application.get_env(
         :database,
         :start_repo,
         false
       ) do
      [Repo]
    else
      []
    end
  end
end
