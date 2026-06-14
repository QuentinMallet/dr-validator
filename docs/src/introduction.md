# Introduction

dr-validator is the authoritative "did the restore actually work?" oracle for NixOS disaster recovery. After a host is restored from backup and `nixos-rebuild switch` completes, dr-validator runs browser-driven E2E tests against live services and produces a versioned JSON report.

## Problem it solves

Filesystem restoration and NixOS activation succeed silently even when an app fails to start, fails to connect to its database, or fails to serve authenticated requests. Shell-level smoke tests catch only the crudest failures. dr-validator catches application-level failures: expired TLS certificates, corrupted key material, misconfigured secrets, or data that didn't survive the restore.

## How it fits into the DR program

The DR program has two paths that converge here:

**Weekly canary (automated)**

```
pi backup-restore-test.service
  → restore borg snapshot to QEMU VM2
  → nixos-rebuild switch
  → dr-validator-run --perimeter <name>
  → report.json
  → prometheus-exporter.sh → pushgateway → Grafana alert
```

**Real DR (operator-driven)**

```
DR ISO boot
  → borg restore
  → nixos-rebuild switch
  → activation hook: dr-validator-run --perimeter <selected>
  → TUI post-reboot summary on first login
```

## Scope

- One umbrella Elixir app. One sub-app per validated service.
- Each sub-app implements `DrValidator.AppValidator` (browser test via Wallaby + headless Chromium).
- The runner iterates a perimeter spec, collects results, writes `report.json` atomically.
- Output schema is stable and versioned (`schema_version: 1`).

## Non-goals

- Generating test fixtures or seeding data (the borg backup is the source of truth)
- Restoring filesystem state (DR ISO scope)
- Long-running observability (OpenTelemetry covers that)
- Full UI regression testing (purpose-built for "service up + data intact", not full UI coverage)

## Upstream spec

Architecture decisions were made in the DR program deep-interview:
`machines_conf:.omc/specs/deep-interview-dr-program.md` (ambiguity 14%, passed 2026-06-14).
