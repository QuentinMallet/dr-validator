defmodule DrValidator.Umbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      apps: [:dr_validator, :dr_validator_openbao],
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [
        dr_validator: [
          applications: [
            dr_validator: :permanent,
            dr_validator_openbao: :permanent
          ],
          include_executables_for: [:unix],
          strip_beams: true
        ]
      ]
    ]
  end

  # Umbrella-level dependencies shared across all apps.
  # Run "mix help deps" for examples and options.
  defp deps do
    []
  end
end
