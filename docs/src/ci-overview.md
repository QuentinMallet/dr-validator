# CI overview

> **TODO when task .11 (CI) lands.**
>
> CI configuration is tracked in beads task .11 (CI pipeline). Once that task is merged, this page will document:
>
> - The GitHub Actions workflow file (`/.github/workflows/ci.yml`)
> - Which jobs run on pull requests vs. merges to master
> - How to run the equivalent checks locally before pushing
> - Nix cache configuration (if any)
>
> Until then, run checks locally:

## Local CI equivalent

```bash
nix develop --command bash -c "mix deps.get && mix format --check-formatted && mix test"
```

## What CI will cover (planned)

| Check | Tool |
|---|---|
| Compilation | `mix compile --warnings-as-errors` |
| Formatting | `mix format --check-formatted` |
| Unit tests | `mix test` |
| Doc build | `nix build .#doc` |

Browser-driven Wallaby tests require headless Chromium and a live target service. These will run in a dedicated integration job, not on every PR.
