# Validator contract

Each validated service is implemented as a sub-app under `apps/dr_validator_<name>/`. The sub-app exports a module that implements the `DrValidator.AppValidator` behaviour.

## Behaviour definition

```elixir
# apps/dr_validator/lib/dr_validator/app_validator.ex
defmodule DrValidator.AppValidator do
  @moduledoc """
  Behaviour for DR app validators. Each app under test implements this.
  """

  alias DrValidator.AppResult

  @doc "Human-readable name identifying this validator."
  @callback name() :: String.t()

  @doc """
  Run the validation for this app.

  Returns `{:ok, result}` on pass or partial, `{:error, result}` on failure.
  """
  @callback run(opts :: map()) :: {:ok, AppResult.t()} | {:error, AppResult.t()}

  @doc """
  Describe the expected data shape for this app, or nil if not applicable.
  """
  @callback expected_data() :: map() | nil
end
```

## Callbacks

### `name/0`

Returns a human-readable string identifying the validator. Used in the report `name` field and in operator-facing output.

```
"OpenBao"
"Zitadel"
"Normatix"
```

### `run/1`

Accepts an `opts` map (passed through from the runner; currently unused but reserved for perimeter-level config). Returns:

- `{:ok, %AppResult{status: :passed, ...}}` — all checks passed
- `{:ok, %AppResult{status: :partial, ...}}` — some checks passed, some did not (service degraded but reachable)
- `{:error, %AppResult{status: :failed, ...}}` — validation failed; `error_message` must be set

The `:partial` status is for cases where the service is reachable but restored data does not fully match expectations (e.g. `expected_data/0` fields differ). Use `:failed` for connectivity failures, authentication failures, or unrecoverable errors.

### `expected_data/0` (optional)

Returns a map describing the expected state of the app after restore, or `nil` if not applicable. The runner does not call this callback directly — it is up to the `run/1` implementation to use it for assertions.

Example:

```elixir
def expected_data do
  %{
    admin_user_exists: true,
    policies: ["app-provisioner", "normatix", "phishguard"]
  }
end
```

## Example implementation

```elixir
defmodule DrValidatorOpenbao.Validator do
  @behaviour DrValidator.AppValidator

  alias DrValidator.AppResult

  @impl true
  def name, do: "OpenBao"

  @impl true
  def expected_data do
    %{policies: ["app-provisioner", "normatix", "phishguard"]}
  end

  @impl true
  def run(_opts) do
    # Browser-driven via Wallaby; headless Chromium required in runtime env
    result =
      %AppResult{
        name: name(),
        status: :passed,
        duration_ms: nil,
        error_message: nil,
        details: %{}
      }

    {:ok, result}
  end
end
```

The real implementation will use Wallaby to drive a headless Chromium session against the live OpenBao UI. See [Adding a new validator](./adding-a-new-validator.md) for the full scaffolding procedure.

## Optional callback

`expected_data/0` is annotated with `@optional_callbacks` in the behaviour — it is safe to omit it if the validator has no expected-data assertions.
