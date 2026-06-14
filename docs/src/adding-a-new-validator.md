# Adding a new validator

One sub-app per service. One PR per validator. Here is the full procedure.

## Prerequisites

- `nix develop` shell active
- Service is reachable from the test host (canary VM2 or DR ISO)
- Headless Chromium available in the shell (provided by `nix develop`)

## Step 1: Create the sub-app

```bash
cd apps
mix new dr_validator_<name> --sup
```

Example for a hypothetical Gitea validator:

```bash
mix new dr_validator_gitea --sup
```

## Step 2: Implement the behaviour

Create `apps/dr_validator_<name>/lib/dr_validator_<name>/validator.ex`:

```elixir
defmodule DrValidatorGitea.Validator do
  @behaviour DrValidator.AppValidator

  alias DrValidator.AppResult

  @impl true
  def name, do: "Gitea"

  @impl true
  def expected_data do
    # Return nil if no expected-data assertions needed.
    # Return a map if run/1 will compare against known-good state.
    %{
      admin_user: "urist",
      repo_count_min: 1
    }
  end

  @impl true
  def run(_opts) do
    # Use Wallaby for browser-driven tests.
    # See https://hexdocs.pm/wallaby for session/page API.
    #
    # Example structure:
    #   {:ok, session} = Wallaby.start_session()
    #   session
    #   |> visit("https://gitea.example.com")
    #   |> assert_has(Query.css("h1", text: "Gitea"))
    #
    # On success:
    result = %AppResult{
      name: name(),
      status: :passed,
      duration_ms: 0,
      error_message: nil,
      details: %{}
    }

    {:ok, result}

    # On failure, return:
    #   {:error, %AppResult{name: name(), status: :failed,
    #                       error_message: "Could not reach login page: ...",
    #                       details: %{}}}
  end
end
```

## Step 3: Add dependency on the core app

In `apps/dr_validator_<name>/mix.exs`, add `:dr_validator` to the deps list:

```elixir
defp deps do
  [
    {:dr_validator, in_umbrella: true},
    {:wallaby, "~> 0.30", runtime: false}
  ]
end
```

## Step 4: Register in DrValidator.Apps

> **TODO when task .9 lands**: `DrValidator.Apps` is the registry that maps perimeter app names to validator modules. Once task .9 (apps registry) is complete, add an entry:
>
> ```elixir
> # apps/dr_validator/lib/dr_validator/apps.ex
> defmodule DrValidator.Apps do
>   @registry %{
>     "openbao" => DrValidatorOpenbao.Validator,
>     "gitea"   => DrValidatorGitea.Validator   # <-- add this line
>   }
>
>   def get(name), do: Map.fetch(@registry, name)
>   def all, do: Map.values(@registry)
> end
> ```
>
> Until the registry lands, validators can be invoked directly in tests.

## Step 5: Write ExUnit tests

```bash
cd apps/dr_validator_<name>
mix test
```

Tests live in `apps/dr_validator_<name>/test/`. At minimum, test that:

- `name/0` returns a non-empty string
- `run/1` returns `{:ok, %AppResult{}}` or `{:error, %AppResult{}}` (not a bare value)
- `expected_data/0` returns a map or nil

Property-based tests via StreamData are available as a project dependency.

## Step 6: Verify the doc build still passes

```bash
nix build .#doc
```

## Checklist

- [ ] Sub-app created with `mix new`
- [ ] `DrValidator.AppValidator` behaviour implemented (all three callbacks)
- [ ] `:dr_validator` umbrella dep declared in mix.exs
- [ ] Registered in `DrValidator.Apps` (when task .9 lands)
- [ ] ExUnit tests pass (`mix test` in the sub-app)
- [ ] `nix build .#doc` succeeds

## Naming conventions

| Thing | Convention | Example |
|---|---|---|
| Sub-app dir | `apps/dr_validator_<service>/` | `apps/dr_validator_openbao/` |
| Mix app name | `:dr_validator_<service>` | `:dr_validator_openbao` |
| Module | `DrValidator<Service>.Validator` | `DrValidatorOpenbao.Validator` |
| Registry key | lowercase service name | `"openbao"` |
