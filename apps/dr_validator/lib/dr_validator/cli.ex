defmodule DrValidator.CLI do
  @moduledoc """
  CLI entrypoint for escript and `mix dr_validator.run` invocation.

  `main/1` parses `argv`, runs the validator pipeline, and returns an integer
  exit code. It is called directly by the `mix dr_validator.run` Mix task and
  by `DrValidator.EscriptMain.main/1` (which wraps it with `System.halt/1` so
  the generated `dr-validator-run` binary exits with the correct `$?`).

  ## Exit codes

    - `0`  — all apps passed (`:passed`)
    - `1`  — at least one app failed, none partial (`:failed`)
    - `2`  — at least one app partial (`:partial`)
    - `3`  — validation ran but the report could not be written to disk
    - `64` — usage error (missing required flag); sysexits.h EX_USAGE

  ## Flags

    - `--perimeter <id>`        (required) perimeter ID to validate
    - `--perimeters-path <p>`   override perimeters JSON file (default: env/system default)
    - `--report-path <p>`       override report output path (must be writable; exit 3 on failure)
    - `--app-timeout-ms <n>`    per-app timeout in milliseconds (must be a positive integer > 0)
    - `--help`                  print usage and exit 0
  """

  alias DrValidator.{Apps, PerimeterLoader, Report, ReportWriter, Runner}

  @usage """
  Usage: dr-validator-run --perimeter <id> [options]

  Options:
    --perimeter <id>        Perimeter ID to validate (required)
    --perimeters-path <p>   Path to perimeters JSON (default: /etc/dr-perimeters.json)
    --report-path <p>       Path for JSON report output (default: /var/log/dr-validator/report.json)
    --app-timeout-ms <n>    Per-app timeout in ms, must be > 0 (default: 300000)
    --help                  Show this help

  Exit codes:
    0   All apps passed
    1   At least one app failed
    2   At least one app partial
    3   Validation ran but report write failed (check --report-path permissions)
    64  Usage error (missing flag, unknown option, or invalid value)
  """

  @ex_usage 64
  @default_perimeters_path "/etc/dr-perimeters.json"

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  CLI entry point. Parses `argv`, runs the validator, returns exit code.

  In escript context, `DrValidator.EscriptMain.main/1` wraps this with
  `System.halt/1`. In test context, call directly and assert on the integer.
  """
  @spec main([String.t()]) :: non_neg_integer()
  def main(argv) do
    case parse_args(argv) do
      :help ->
        IO.puts(@usage)
        0

      {:error, :usage_error} ->
        IO.puts(:stderr, "error: invalid or missing arguments\n")
        IO.puts(:stderr, @usage)
        @ex_usage

      {:ok, opts} ->
        run(opts)
    end
  end

  @doc """
  Parse `argv` into an opts map.

  Returns:
    - `:help`                   — `--help` flag present
    - `{:ok, opts}`             — valid args; opts has `:perimeter` (required) plus optional keys
    - `{:error, :usage_error}`  — `--perimeter` missing, unknown option present,
                                  or `--app-timeout-ms` is not a positive integer
  """
  @spec parse_args([String.t()]) :: :help | {:ok, map()} | {:error, :usage_error}
  def parse_args(argv) do
    {parsed, _rest, invalid} =
      OptionParser.parse(argv,
        strict: [
          perimeter: :string,
          perimeters_path: :string,
          report_path: :string,
          app_timeout_ms: :integer,
          help: :boolean
        ]
      )

    timeout = Keyword.get(parsed, :app_timeout_ms)

    cond do
      Keyword.get(parsed, :help) ->
        :help

      invalid != [] ->
        {:error, :usage_error}

      is_nil(Keyword.get(parsed, :perimeter)) ->
        {:error, :usage_error}

      not (is_nil(timeout) or timeout > 0) ->
        {:error, :usage_error}

      true ->
        opts = %{
          perimeter: Keyword.fetch!(parsed, :perimeter),
          perimeters_path: Keyword.get(parsed, :perimeters_path),
          report_path: Keyword.get(parsed, :report_path),
          app_timeout_ms: timeout
        }

        {:ok, opts}
    end
  end

  @doc """
  Map a `Report.overall_status` atom to an integer exit code.
  """
  @spec exit_code_for(Report.overall_status()) :: 0 | 1 | 2
  def exit_code_for(:passed), do: 0
  def exit_code_for(:failed), do: 1
  def exit_code_for(:partial), do: 2

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp run(opts) do
    perimeter_id = opts.perimeter
    perimeters_path = opts.perimeters_path
    resolved_path = perimeters_path || System.get_env("DR_PERIMETERS_PATH", @default_perimeters_path)

    loader_args =
      if perimeters_path do
        [perimeters_path, perimeter_id]
      else
        [perimeter_id]
      end

    case apply(PerimeterLoader, :get, loader_args) do
      {:error, :not_found} ->
        IO.puts(:stderr, "error: perimeter #{inspect(perimeter_id)} not found in #{resolved_path}")
        1

      {:error, :file_not_found} ->
        IO.puts(:stderr, "error: perimeters file not found: #{resolved_path}")
        1

      {:error, :permission_denied} ->
        IO.puts(:stderr, "error: permission denied reading perimeters file: #{resolved_path}")
        1

      {:error, {:file_error, reason}} ->
        IO.puts(:stderr, "error: reading perimeters file #{resolved_path}: #{inspect(reason)}")
        1

      {:error, :malformed} ->
        IO.puts(:stderr, "error: perimeters file is malformed: #{resolved_path}")
        1

      {:ok, perimeter} ->
        run_perimeter(perimeter, opts)
    end
  end

  defp run_perimeter(perimeter, opts) do
    unregistered = Enum.reject(perimeter.apps, &Apps.lookup/1)

    if unregistered != [] do
      IO.puts(
        :stderr,
        "warning: no validator registered for apps: #{Enum.join(unregistered, ", ")}"
      )
    end

    runner_opts =
      [validator_lookup: &Apps.lookup/1]
      |> maybe_put(:app_timeout_ms, opts.app_timeout_ms)

    report = Runner.run(perimeter, runner_opts)

    case write_report(report, opts.report_path) do
      :ok ->
        exit_code_for(report.overall_status)

      {:error, reason} ->
        IO.puts(
          :stderr,
          "error: failed to write report to #{opts.report_path || "(default path)"}: #{inspect(reason)}"
        )

        3
    end
  end

  defp write_report(report, path) do
    writer = Application.get_env(:dr_validator, :report_writer, ReportWriter)
    if path, do: writer.write(report, path), else: writer.write(report)
  end

  defp maybe_put(kw, _key, nil), do: kw
  defp maybe_put(kw, key, value), do: Keyword.put(kw, key, value)
end
