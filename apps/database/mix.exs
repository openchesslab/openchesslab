defmodule Database.MixProject do
  use Mix.Project

  def project do
    [
      app: :database,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {OpenChessLab.Database.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:benchee, "~> 1.5", only: :dev},
      # Migrations seed reference data (openings) by replaying with the rules.
      {:chess, in_umbrella: true},
      {:ecto_sql, "~> 3.14.0"},
      {:postgrex, "~> 0.22.4"}
    ]
  end
end
