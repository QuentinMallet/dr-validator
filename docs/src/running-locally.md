# Running locally

## Development shell

```bash
nix develop
```

This provides Elixir, Erlang, mix2nix, elixir-ls, and headless Chromium. All subsequent commands assume you are inside this shell.

## Fetch dependencies

```bash
mix deps.get
```

## Run tests

```bash
# All apps
mix test

# Single sub-app
mix test apps/dr_validator/

# Specific test file
mix test apps/dr_validator/test/dr_validator/report_test.exs
```

## Format and check

```bash
mix format --check-formatted
```

## Interactive shell

```bash
iex -S mix
```

## CLI entrypoint

> **TODO when task .7 (report writer) and task .10 (CLI) land.**
>
> The `mix dr_validator.run` Mix task and the `dr-validator-run` escript are implemented in tasks .7 and .10 respectively. Once those are merged, this section will document:
>
> ```bash
> # Dev: run via Mix task
> mix dr_validator.run --perimeter default
>
> # Prod: escript (available in nix develop and DR ISO closure)
> dr-validator-run --perimeter canary
>
> # Output
> cat /var/log/dr-validator/report.json
> ```

## Chromium requirement

Wallaby drives a headless Chromium session. The `nix develop` shell provides Chromium via the flake's `devShells.default`. In production (DR ISO), Chromium is in the ISO closure — no network fetch needed at runtime.

If you run outside `nix develop`, set `WALLABY_CHROME_PATH` to point to a Chromium binary:

```bash
WALLABY_CHROME_PATH=$(which chromium) mix test
```

## Building the docs

```bash
nix build .#doc
# Opens at ./result/index.html
```
