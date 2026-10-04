#!/usr/bin/env bash
# Build the app and zip it for a release. Usage: VERSION=x.y.z scripts/package.sh
# Writes dist/SSM-<version>-<arch>.zip and its .sha256, and prints the zip path.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${VERSION:?set VERSION to the release version, for example 0.1.0}"
arch="$(uname -m)"
zip="$root/dist/SSM-${VERSION}-${arch}.zip"

VERSION="$VERSION" bash "$root/build-app.sh" --no-open
mkdir -p "$root/dist"
rm -f "$zip" "$zip.sha256"
ditto -c -k --keepParent "$root/.build/SSM.app" "$zip"
(cd "$root/dist" && shasum -a 256 "$(basename "$zip")" > "$(basename "$zip").sha256")
echo "$zip"
