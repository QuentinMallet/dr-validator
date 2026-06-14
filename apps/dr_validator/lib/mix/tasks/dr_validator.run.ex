defmodule Mix.Tasks.DrValidator.Run do
  @shortdoc "Run DR validation for a perimeter"

  @moduledoc """
  Runs disaster-recovery validation for a named perimeter.

      mix dr_validator.run --perimeter <id> [options]

  ## Options

    * `--perimeter <id>`       — perimeter ID to validate (required)
    * `--perimeters-path <p>`  — path to perimeters JSON file
    * `--report-path <p>`      — path for JSON report output
    * `--app-timeout-ms <n>`   — per-app timeout in milliseconds
    * `--help`                 — show usage

  ## Exit codes

    * `0`  — all apps passed
    * `1`  — at least one app failed
    * `2`  — at least one app partial
    * `64` — usage error (missing required flag)

  This task is a thin wrapper around `DrValidator.CLI.main/1`.
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    rc = DrValidator.CLI.main(argv)

    if rc != 0 do
      exit({:shutdown, rc})
    end
  end
end
