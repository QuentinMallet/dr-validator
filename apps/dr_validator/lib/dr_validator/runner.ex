defmodule DrValidator.Runner do
  @moduledoc """
  Runs all app validators for a perimeter, collecting results into a Report.

  ## Design note — plain module, not GenServer

  Runner is implemented as a plain module with a synchronous `run/2` entry
  point rather than a GenServer. Rationale:

  - The caller already owns the execution context (a scheduled task, a
    supervision-tree worker, or a test process). Adding a GenServer wrapper
    would create an extra process boundary with no architectural benefit.
  - There is no stateful lifecycle to manage between calls: each `run/2`
    call is independent and produces a self-contained `%Report{}`.
  - If future requirements call for live progress queries, cancellation, or
    OTP-supervised parallel execution, a GenServer wrapper can be layered on
    top of this module without changing the `run/2` contract.

  ## Validator injection

  Validators are resolved per-app name via one of two opts:

  - `:validators` — `%{"openbao" => MyModule, ...}` map
  - `:validator_lookup` — `fn(name :: String.t()) :: module() | nil` (takes
    precedence over `:validators`)

  ## Concurrency model

  Each app validator runs inside a `Task.async` call so that `:app_timeout_ms`
  can be enforced with `Task.yield` + `Task.shutdown(:brutal_kill)`. The task
  body is wrapped in `try/rescue` so that exceptions are captured as `:failed`
  `AppResult` values. EXIT signals (e.g. `exit/1` in a validator) are not caught
  in the task body; when the caller traps exits, `Task.yield` surfaces these as
  `{:exit, reason}` which is handled by the dedicated clause below. Execution
  order matches `perimeter.apps` (sequential Enum.map).
  """

  alias DrValidator.{AppResult, Perimeter, Report}

  @default_timeout_ms :timer.minutes(5)

  @doc """
  Run all app validators for `perimeter` and return a `%Report{}`.

  Options:
  - `:validators` — map of `%{app_name => validator_module}`
  - `:validator_lookup` — `fn(name) :: module() | nil` (overrides `:validators`)
  - `:app_timeout_ms` — per-app deadline in milliseconds (default: 5 min)
  - `:report_writer` — `fn(%Report{}) :: any()` called after aggregation;
    defaults to identity. ReportWriter (task .6) is injected here once landed.
  """
  @spec run(Perimeter.t(), keyword()) :: Report.t()
  def run(%Perimeter{} = perimeter, opts \\ []) do
    timeout_ms = Keyword.get(opts, :app_timeout_ms, @default_timeout_ms)
    lookup = build_lookup(opts)
    report_writer = Keyword.get(opts, :report_writer, &Function.identity/1)
    started_at = DateTime.utc_now()

    app_results =
      Enum.map(perimeter.apps, fn app_name ->
        run_app(app_name, lookup, timeout_ms, opts)
      end)

    report =
      Report.new(
        perimeter_id: perimeter.id,
        apps: app_results,
        started_at: started_at,
        completed_at: DateTime.utc_now()
      )

    report_writer.(report)
    report
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp build_lookup(opts) do
    case Keyword.get(opts, :validator_lookup) do
      nil ->
        validators = Keyword.get(opts, :validators, %{})
        fn name -> Map.get(validators, name) end

      f ->
        f
    end
  end

  defp run_app(app_name, lookup, timeout_ms, opts) do
    validator = lookup.(app_name)

    if is_nil(validator) do
      %AppResult{
        name: app_name,
        status: :failed,
        duration_ms: 0,
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now(),
        error_message: "no validator registered for #{inspect(app_name)}"
      }
    else
      execute_validator(app_name, validator, timeout_ms, opts)
    end
  end

  defp execute_validator(app_name, validator, timeout_ms, opts) do
    t0 = System.monotonic_time(:millisecond)
    started_at = DateTime.utc_now()
    opts_map = opts |> Keyword.drop([:validators, :validator_lookup, :app_timeout_ms, :report_writer]) |> Map.new()

    # Wrap in try/rescue so a validator that raises an exception returns a value
    # instead of propagating. EXIT signals from exit/1 are intentionally not
    # caught here: they cause the task process to exit, which Task.yield surfaces
    # as {:exit, reason} (when the caller traps exits) and handled below.
    task =
      Task.async(fn ->
        try do
          validator.run(opts_map)
        rescue
          e -> {:crashed, Exception.message(e)}
        end
      end)

    elapsed_ms = fn -> System.monotonic_time(:millisecond) - t0 end

    result =
      case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
        {:ok, {:ok, %AppResult{} = r}} ->
          %{r | name: app_name, duration_ms: elapsed_ms.(), started_at: started_at, completed_at: DateTime.utc_now()}

        {:ok, {:error, %AppResult{} = r}} ->
          %{r | name: app_name, duration_ms: elapsed_ms.(), started_at: started_at, completed_at: DateTime.utc_now()}

        {:ok, {:crashed, msg}} ->
          %AppResult{
            name: app_name,
            status: :failed,
            duration_ms: elapsed_ms.(),
            started_at: started_at,
            completed_at: DateTime.utc_now(),
            error_message: "crashed: #{msg}"
          }

        # Task.yield returned nil (timeout), Task.shutdown returned nil (killed).
        nil ->
          %AppResult{
            name: app_name,
            status: :failed,
            duration_ms: elapsed_ms.(),
            started_at: started_at,
            completed_at: DateTime.utc_now(),
            error_message: "timeout after #{elapsed_ms.()}ms"
          }

        # Unexpected exit (e.g. external kill signal).
        {:exit, reason} ->
          %AppResult{
            name: app_name,
            status: :failed,
            duration_ms: elapsed_ms.(),
            started_at: started_at,
            completed_at: DateTime.utc_now(),
            error_message: "crashed: #{inspect(reason)}"
          }
      end

    result
  end
end
