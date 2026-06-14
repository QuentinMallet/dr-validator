#!/usr/bin/env bash
# Smoke test: nix build .#default produces a usable escript
set -e

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

echo "==> nix build .#default"
nix build .#default --no-link --print-out-paths

echo "==> ./result/bin/dr-validator-run --help"
./result/bin/dr-validator-run --help

echo "==> PASS"
