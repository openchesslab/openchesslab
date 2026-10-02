defmodule OpenChessLab.Database.Release do
  @moduledoc false

  @app :database

  @spec migrate() :: :ok
  def migrate do
    _result =
      Application.load(@app)

    for repo <- repos() do
      {:ok, _result, _started_apps} =
        Ecto.Migrator.with_repo(
          repo,
          fn repo ->
            Ecto.Migrator.run(
              repo,
              :up,
              all: true
            )
          end
        )
    end

    :ok
  end

  defp repos do
    Application.fetch_env!(
      @app,
      :ecto_repos
    )
  end
end
