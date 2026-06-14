# DrValidatorOpenbao

DR validator for OpenBao — checks health, KV mount, and canary secret after
a restore activation.

## Configuration

`DrValidator.Apps.Openbao.RestoreTest.run/1` accepts an opts map:

| Key | Required | Default | Description |
|-----|----------|---------|-------------|
| `:base_url` | no | `http://127.0.0.1:8200` | OpenBao base URL. Non-localhost requires `:allow_remote: true`. |
| `:token` | **yes** | — | Vault token. Falls back to `DR_OPENBAO_TOKEN` env var. Fails closed if neither set. |
| `:allow_remote` | no | `false` | Allow non-localhost `:base_url`. |

### Token resolution

The token is resolved in this order (fail-closed — no default):

1. `:token` key in the opts map
2. `DR_OPENBAO_TOKEN` environment variable
3. `{:error, %AppResult{status: :failed}}` — no silent fallback to a dev root token

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `dr_validator_openbao` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:dr_validator_openbao, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/dr_validator_openbao>.

