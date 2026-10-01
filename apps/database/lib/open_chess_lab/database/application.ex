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
    [Repo]
  end
end
