defmodule Analysis.MixProject do
  use Mix.Project

  def project do
    [
      app: :analysis,
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
      mod: {Analysis.Application, []},
      extra_applications: [:logger, :crypto]
    ]
  end

  defp deps do
    [
      {:chess, in_umbrella: true},
      {:database, in_umbrella: true},
      {:features, in_umbrella: true},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.3.0"},
      {:horde, "~> 0.10"},
      {:benchee, "~> 1.5", only: :dev}
    ]
  end
end
