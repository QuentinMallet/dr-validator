defmodule DrValidator.Umbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      apps: [:dr_validator],
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Umbrella-level dependencies shared across all apps.
  # Run "mix help deps" for examples and options.
  defp deps do
    []
  end
end
