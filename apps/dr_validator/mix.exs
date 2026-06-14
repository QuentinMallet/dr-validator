defmodule DrValidator.MixProject do
  use Mix.Project

  def project do
    [
      app: :dr_validator,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      escript: [main_module: DrValidator.CLI, name: "dr-validator-run"],
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jason, "~> 1.4"},
      {:stream_data, "~> 1.0", only: [:test, :dev]},
      {:wallaby, "~> 0.30", only: [:test, :dev], runtime: false}
    ]
  end
end
