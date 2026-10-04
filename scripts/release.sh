#!/usr/bin/env bash
# Cut a release by hand on a Mac. Usage: release.sh <x.y.z> [--dry-run]
# Builds and zips the app, creates the Forgejo release at origin/main, uploads the zip
# and its sha256, then reads both assets back. The fleet mirror copies them to GitHub.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${1:?usage: release.sh <x.y.z> [--dry-run]}"
dry=0
[ "${2:-}" = "--dry-run" ] && dry=1
tag="v${version}"
owner=coilyco
repo=ssm-app

fail() { echo "release: $*" >&2; exit 1; }

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must be x.y.z, got '$version'"
git -C "$root" fetch -q origin main
[ -z "$(git -C "$root" status --porcelain)" ] || fail "the worktree is not clean"
sha="$(git -C "$root" rev-parse HEAD)"
[ "$sha" = "$(git -C "$root" rev-parse origin/main)" ] || fail "HEAD is not origin/main"

# A mirrored asset is never overwritten, so refuse a tag that already has a release.
if aosguard ops forgejo release list "$owner" "$repo" --limit 50 | jq -e --arg t "$tag" 'any(.[]; .tag_name == $t)' >/dev/null; then
  fail "$tag already has a release"
fi

zip="$(VERSION="$version" bash "$root/scripts/package.sh" | tail -1)"
sum="$(cut -d' ' -f1 "$zip.sha256")"
echo "built $zip sha256 $sum at $sha"
if [ "$dry" = 1 ]; then
  echo "dry run: would create $tag on $owner/$repo and upload $(basename "$zip") and its .sha256"
  exit 0
fi

body="$(basename "$zip") sha256 $sum, commit $sha"
id="$(aosguard ops forgejo release create "$owner" "$repo" --tag_name "$tag" --name "SSM $tag" \
  --target_commitish "$sha" --body "$body" | jq -r .id)"
[ -n "$id" ] && [ "$id" != null ] || fail "release create returned no id"
for file in "$zip" "$zip.sha256"; do
  aosguard ops forgejo release upload-asset "$owner" "$repo" "$id" --name "$(basename "$file")" --attachment "$file" > /dev/null
done

# Read the zip back through its public URL and compare the checksum, since an upload
# that exits 0 is a claim about sending.
url="$(aosguard ops forgejo release get "$owner" "$repo" "$id" | jq -r --arg n "$(basename "$zip")" '.assets[] | select(.name == $n) | .browser_download_url')"
[ -n "$url" ] || fail "the zip is not on release $id"
back="$(curl -fsSL --max-time 120 "$url" | shasum -a 256 | cut -d' ' -f1)"
[ "$back" = "$sum" ] || fail "downloaded checksum $back does not match $sum"
echo "released $tag, asset read back and matched: $url"
