# Report schema

The runner writes a single JSON file to `/var/log/dr-validator/report.json` (atomic write — temp file + rename). The schema is versioned; breaking changes bump `schema_version`.

## Current schema (version 1)

```json
{
  "schema_version": 1,
  "perimeter_id": "default",
  "started_at": "2026-06-14T01:00:00.000000Z",
  "completed_at": "2026-06-14T01:03:47.123456Z",
  "overall_status": "passed",
  "apps": [
    {
      "name": "OpenBao",
      "status": "passed",
      "duration_ms": 4200,
      "started_at": "2026-06-14T01:00:00.100000Z",
      "completed_at": "2026-06-14T01:00:04.300000Z",
      "error_message": null,
      "details": {}
    }
  ]
}
```

## Top-level fields

| Field | Type | Notes |
|---|---|---|
| `schema_version` | integer | Always `1` in the current release. |
| `perimeter_id` | string | Perimeter name passed to `--perimeter`. |
| `started_at` | ISO 8601 datetime or null | When the runner started. |
| `completed_at` | ISO 8601 datetime or null | When the runner finished. |
| `overall_status` | `"passed"` \| `"failed"` \| `"partial"` | Derived from app statuses (see below). |
| `apps` | array of AppResult | One entry per validator run. |

## `overall_status` derivation

| Condition | `overall_status` |
|---|---|
| All apps `:passed` | `"passed"` |
| Any app `:partial` (regardless of `:failed` count) | `"partial"` |
| Any app `:failed`, none `:partial` | `"failed"` |

## Per-app fields (`AppResult`)

| Field | Type | Notes |
|---|---|---|
| `name` | string | From `AppValidator.name/0`. |
| `status` | `"passed"` \| `"failed"` \| `"partial"` | Result of this validator. |
| `duration_ms` | integer or null | Wall-clock duration of `run/1` in milliseconds. |
| `started_at` | ISO 8601 datetime or null | When this validator started. |
| `completed_at` | ISO 8601 datetime or null | When this validator finished. |
| `error_message` | string or null | Human-readable failure reason. Required when `status` is `"failed"`. |
| `details` | object | Freeform validator-specific data. Empty object `{}` if unused. |

## Elixir structs

```elixir
defmodule DrValidator.Report do
  @enforce_keys [:perimeter_id, :apps]
  defstruct [
    :perimeter_id,
    :started_at,
    :completed_at,
    :overall_status,
    apps: [],
    schema_version: 1
  ]
end

defmodule DrValidator.AppResult do
  @enforce_keys [:name, :status]
  defstruct [
    :name,
    :status,
    :duration_ms,
    :started_at,
    :completed_at,
    :error_message,
    details: %{}
  ]
end
```

Both structs derive `Jason.Encoder` and serialize to JSON via `Jason.encode!/1`.

## Stability guarantee

`schema_version: 1` is stable. Fields will not be removed or renamed in a patch. New optional fields may be added; consumers must ignore unknown fields. A breaking change will increment `schema_version` and require a coordinated update with `machines_conf`'s Prometheus exporter and DR ISO hooks.

## Example: partial result

```json
{
  "schema_version": 1,
  "perimeter_id": "canary",
  "started_at": "2026-06-14T01:00:00Z",
  "completed_at": "2026-06-14T01:05:12Z",
  "overall_status": "partial",
  "apps": [
    {
      "name": "OpenBao",
      "status": "passed",
      "duration_ms": 3100,
      "started_at": "2026-06-14T01:00:00Z",
      "completed_at": "2026-06-14T01:00:03Z",
      "error_message": null,
      "details": {}
    },
    {
      "name": "Zitadel",
      "status": "partial",
      "duration_ms": 62000,
      "started_at": "2026-06-14T01:00:03Z",
      "completed_at": "2026-06-14T01:01:05Z",
      "error_message": null,
      "details": {
        "expected_users": 3,
        "found_users": 2,
        "missing": ["alice@example.com"]
      }
    }
  ]
}
```
