#!/usr/bin/env bash
# Open the homebrew-tap pull request that points Casks/ssm.rb at a release.
# Usage: tap-cask.sh <x.y.z>. Reads the checksum from the release's .sha256 asset.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${1:?usage: tap-cask.sh <x.y.z>}"
tag="v${version}"
asset="SSM-${version}-arm64.zip"

fail() { echo "tap-cask: $*" >&2; exit 1; }
forgejo() { aosguard ops forgejo "$@"; }

id="$(forgejo release list coilyco ssm-app --limit 50 --query "[?tag_name=='$tag'].id | [0]")"
[ "$id" != null ] || fail "$tag has no release, run release.sh first"
url="$(forgejo release get coilyco ssm-app "$id" --query "assets[?name=='$asset.sha256'].browser_download_url | [0]")"
[ "$url" != null ] || fail "the release has no $asset.sha256"
sum="$(curl -fsSL --max-time 60 "$url" | cut -d' ' -f1)"
[[ "$sum" =~ ^[0-9a-f]{64}$ ]] || fail "unexpected checksum '$sum'"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git clone -q https://forgejo.coilysiren.me/coilyco/homebrew-tap.git "$work/tap"
branch="ssm-cask-${version}"
git -C "$work/tap" switch -q -c "$branch"
mkdir -p "$work/tap/Casks"
bash "$root/scripts/render-cask.sh" "$version" "$sum" "$work/tap/Casks/ssm.rb"
git -C "$work/tap" add Casks/ssm.rb
git -C "$work/tap" commit -q -m "feat(ssm): point the ssm cask at ssm-app ${tag}"
git -C "$work/tap" push -q origin "$branch"
forgejo pr create coilyco homebrew-tap --head "$branch" --base main \
  --title "feat(ssm): point the ssm cask at ssm-app ${tag}" \
  --body "Casks/ssm.rb for ssm-app ${tag}, checksum ${sum}, rendered by ssm-app scripts/render-cask.sh."
