#!/usr/bin/env bash
# Regenerate Resources/AppIcon.icns from scripts/make-icon.swift. Usage: make-icon.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
swift "$root/scripts/make-icon.swift" "$work/AppIcon.iconset"
mkdir -p "$root/Resources"
iconutil -c icns "$work/AppIcon.iconset" -o "$root/Resources/AppIcon.icns"
echo "wrote $root/Resources/AppIcon.icns"
