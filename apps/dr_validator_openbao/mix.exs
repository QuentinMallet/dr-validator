defmodule DrValidatorOpenbao.MixProject do
  use Mix.Project

  def project do
    [
      app: :dr_validator_openbao,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:dr_validator, in_umbrella: true},
      {:httpoison, "~> 2.0"},
      {:jason, "~> 1.4"},
      {:bypass, "~> 2.1", only: [:test]},
      {:stream_data, "~> 1.0", only: [:test, :dev]}
    ]
  end
end
