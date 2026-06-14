defmodule DrValidator.CLI do
  @moduledoc """
  CLI entrypoint for escript invocation.

  `main/1` is the escript entry point called with `System.argv()` by the
  generated `dr-validator-run` binary. It is also invoked by the
  `mix dr_validator.run` task so the two entrypoints share identical
  arg-parsing and dispatch logic.

  ## Exit codes

    - `0`  — all apps passed (`:passed`)
    - `1`  — at least one app failed, none partial (`:failed`)
    - `2`  — at least one app partial (`:partial`)
    - `64` — usage error (missing required flag); sysexits.h EX_USAGE

  ## Flags

    - `--perimeter <id>`        (required) perimeter ID to validate
    - `--perimeters-path <p>`   override perimeters JSON file (default: env/system default)
    - `--report-path <p>`       override report output path
    - `--app-timeout-ms <n>`    per-app timeout in milliseconds
    - `--help`                  print usage and exit 0
  """

  alias DrValidator.{Apps, PerimeterLoader, Report, ReportWriter, Runner}

  @usage """
  Usage: dr-validator-run --perimeter <id> [options]

  Options:
    --perimeter <id>        Perimeter ID to validate (required)
    --perimeters-path <p>   Path to perimeters JSON (default: /etc/dr-perimeters.json)
    --report-path <p>       Path for JSON report output (default: /var/log/dr-validator/report.json)
    --app-timeout-ms <n>    Per-app timeout in ms (default: 300000)
    --help                  Show this help
  """

  @ex_usage 64

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Escript entry point. Parses `argv`, runs the validator, returns exit code.

  In escript context, call `System.halt(main(System.argv()))`.
  In test context, call directly and assert on the returned integer.
  """
  @spec main([String.t()]) :: non_neg_integer()
  def main(argv) do
    case parse_args(argv) do
      :help ->
        IO.puts(@usage)
        0

      {:error, :usage_error} ->
        IO.puts(:stderr, "error: --perimeter is required\n")
        IO.puts(:stderr, @usage)
        @ex_usage

      {:ok, opts} ->
        run(opts)
    end
  end

  @doc """
  Parse `argv` into an opts map.

  Returns:
    - `:help`               — `--help` flag present
    - `{:ok, opts}`         — valid args; opts has `:perimeter` (required) plus optional keys
    - `{:error, :usage_error}` — `--perimeter` missing
  """
  @spec parse_args([String.t()]) :: :help | {:ok, map()} | {:error, :usage_error}
  def parse_args(argv) do
    {parsed, _rest, _invalid} =
      OptionParser.parse(argv,
        strict: [
          perimeter: :string,
          perimeters_path: :string,
          report_path: :string,
          app_timeout_ms: :integer,
          help: :boolean
        ]
      )

    cond do
      Keyword.get(parsed, :help) ->
        :help

      is_nil(Keyword.get(parsed, :perimeter)) ->
        {:error, :usage_error}

      true ->
        opts = %{
          perimeter: Keyword.fetch!(parsed, :perimeter),
          perimeters_path: Keyword.get(parsed, :perimeters_path),
          report_path: Keyword.get(parsed, :report_path),
          app_timeout_ms: Keyword.get(parsed, :app_timeout_ms)
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

    loader_args =
      if perimeters_path do
        [perimeters_path, perimeter_id]
      else
        [perimeter_id]
      end

    case apply(PerimeterLoader, :get, loader_args) do
      {:error, :not_found} ->
        IO.puts(:stderr, "error: perimeter #{inspect(perimeter_id)} not found")
        1

      {:error, :file_not_found} ->
        IO.puts(:stderr, "error: perimeters file not found")
        1

      {:error, :malformed} ->
        IO.puts(:stderr, "error: perimeters file is malformed")
        1

      {:ok, perimeter} ->
        run_perimeter(perimeter, opts)
    end
  end

  defp run_perimeter(perimeter, opts) do
    runner_opts =
      [validator_lookup: &Apps.lookup/1]
      |> maybe_put(:app_timeout_ms, opts.app_timeout_ms)

    report = Runner.run(perimeter, runner_opts)

    write_report(report, opts.report_path)

    exit_code_for(report.overall_status)
  end

  defp write_report(report, nil), do: ReportWriter.write(report)
  defp write_report(report, path), do: ReportWriter.write(report, path)

  defp maybe_put(kw, _key, nil), do: kw
  defp maybe_put(kw, key, value), do: Keyword.put(kw, key, value)
end
