defmodule DrValidator.Perimeter do
  @moduledoc """
  Struct representing a DR validation perimeter.

  Mirrors the JSON shape emitted by the `services.drProgram.perimeters` NixOS
  option into `/etc/dr-perimeters.json`.

  Fields
  - `:id`                  – unique perimeter identifier (e.g. `"pi-full"`)
  - `:host`                – target host name (e.g. `"pi"`)
  - `:apps`                – list of app names to validate (e.g. `["openbao", "zitadel"]`)
  - `:canary`              – whether this perimeter participates in the weekly canary run
  - `:archive_age_days_max` – optional max archive age offered in TUI shortcut menu
  """

  @type t :: %__MODULE__{
          id: String.t(),
          host: String.t(),
          apps: [String.t()],
          canary: boolean(),
          archive_age_days_max: non_neg_integer() | nil
        }

  @enforce_keys [:id, :host, :apps, :canary]
  defstruct [:id, :host, :apps, :canary, archive_age_days_max: nil]
end
