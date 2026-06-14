# apps/

Umbrella sub-apps for dr-validator.

## Naming convention

| Pattern | Purpose |
|---------|---------|
| `dr_validator` | Core umbrella app — `DrValidator.Runner` GenServer, `DrValidator.AppValidator` behaviour, `DrValidator.Report` struct, perimeter spec loader, CLI task |
| `dr_validator_<service>` | Per-service validator sub-app — implements `DrValidator.AppValidator` for a specific service (e.g. `dr_validator_openbao`) |

## Adding a new service validator

```bash
cd apps
mix new dr_validator_<service>
```

Then in `apps/dr_validator_<service>/mix.exs`:
- Add `{:dr_validator, in_umbrella: true}` to `deps/0`
- Implement the `DrValidator.AppValidator` behaviour in a module named `DrValidator.<Service>.Validator`

The umbrella root `mix.exs` lists `:apps` explicitly — update it when adding a new sub-app:

```elixir
apps: [:dr_validator, :dr_validator_<service>]
```
