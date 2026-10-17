defmodule Features.MixProject do
  use Mix.Project

  def project do
    [
      app: :features,
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
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:benchee, "~> 1.5", only: :dev},
      # Test-only: the differential harness validates this app's chess core
      # against the gameplay engine (F3 consolidation decision comes later).
      {:chess, in_umbrella: true, only: :test}
    ]
  end
end
