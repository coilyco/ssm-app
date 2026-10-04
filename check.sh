#!/usr/bin/env bash
# Run every SSM app check against a fake aws and a fixture descriptions overlay.
# Nothing here reaches AWS or a real parameter. Usage: check.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

swift build --package-path "$here"
bin="$(swift build --package-path "$here" --show-bin-path)"

echo "== core checks"
"$bin/ssm-check"

echo "== model driver"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
"$bin/ssm-check" --fake "$tmp" > /dev/null
mkdir -p "$tmp/repo/data" "$tmp/no-checkout"
# A fixture, never the real index: one overlay-only entry, one shadowing an SSM one.
printf 'descriptions:\n  /authelia/jwt-secret: "From the overlay"\n  /zulip/secret-key: "Overlay wins"\n' > "$tmp/repo/data/ssm-descriptions.yaml"
printf '[default]\nregion = us-east-1\n[profile admin]\n' > "$tmp/config"
drive() {
  SSM_APP_DRIVE=1 \
    SSM_APP_AWS="$tmp/aws" \
    FAKE_AWS_STATE="$tmp/state.json" \
    FAKE_AWS_LOG="$tmp/calls.jsonl" \
    SSM_APP_REPO="$1" \
    AWS_CONFIG_FILE="$tmp/config" \
    "$bin/SsmApp"
}
echo "-- with a descriptions overlay checkout"
cp "$tmp/state.json" "$tmp/state.seed"
drive "$tmp/repo"
echo "-- installed, no checkout"
cp "$tmp/state.seed" "$tmp/state.json"
: > "$tmp/calls.jsonl"
drive "$tmp/no-checkout"
