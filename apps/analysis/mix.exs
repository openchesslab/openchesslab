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

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Analysis.Application, []},
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:chess, in_umbrella: true},
      {:position_db, in_umbrella: true},
      {:horde, "~> 0.10"}
    ]
  end
end
