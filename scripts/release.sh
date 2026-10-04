#!/usr/bin/env bash
# Cut a release by hand on a Mac. Usage: release.sh <x.y.z> [--dry-run]
# Builds and zips the app, creates the Forgejo release at origin/main, uploads the zip
# and its sha256, then reads the zip back. The fleet mirror copies the assets to GitHub.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${1:?usage: release.sh <x.y.z> [--dry-run]}"
dry=0
[ "${2:-}" = "--dry-run" ] && dry=1
tag="v${version}"
owner=coilyco
repo=ssm-app

fail() { echo "release: $*" >&2; exit 1; }
# aosguard prints a scalar raw and anything larger as YAML, so every read is a projection.
forgejo() { aosguard ops forgejo "$@"; }

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must be x.y.z, got '$version'"
git -C "$root" fetch -q origin main
[ -z "$(git -C "$root" status --porcelain)" ] || fail "the worktree is not clean"
sha="$(git -C "$root" rev-parse HEAD)"
[ "$sha" = "$(git -C "$root" rev-parse origin/main)" ] || fail "HEAD is not origin/main"

# A mirrored asset is never overwritten. A release with assets is final, and one with
# none, left by an interrupted run at this same commit, is finished instead of redone.
id="$(forgejo release list "$owner" "$repo" --limit 50 --query "[?tag_name=='$tag'].id | [0]")"
if [ "$id" != null ]; then
  have="$(forgejo release get "$owner" "$repo" "$id" --query 'length(assets)')"
  [ "$have" = 0 ] || fail "$tag already has $have assets, cut a new version"
  cut="$(forgejo release get "$owner" "$repo" "$id" --query target_commitish)"
  [ "$cut" = "$sha" ] || fail "$tag was cut at $cut, not $sha"
  echo "resuming release $id for $tag, it has no assets yet"
fi

zip="$(VERSION="$version" bash "$root/scripts/package.sh" | tail -1)"
sum="$(cut -d' ' -f1 "$zip.sha256")"
echo "built $zip sha256 $sum at $sha"
if [ "$dry" = 1 ]; then
  echo "dry run: would release $tag on $owner/$repo with $(basename "$zip") and its .sha256"
  exit 0
fi

if [ "$id" = null ]; then
  body="$(basename "$zip") sha256 $sum, commit $sha"
  id="$(forgejo release create "$owner" "$repo" --tag_name "$tag" --name "SSM $tag" \
    --target_commitish "$sha" --body "$body" --query id)"
  [[ "$id" =~ ^[0-9]+$ ]] || fail "release create returned '$id', not an id"
fi
for file in "$zip" "$zip.sha256"; do
  forgejo release upload-asset "$owner" "$repo" "$id" --name "$(basename "$file")" --attachment "$file" > /dev/null
done

# An upload that exits 0 is a claim about sending, so read the zip back and compare.
url="$(forgejo release get "$owner" "$repo" "$id" --query "assets[?name=='$(basename "$zip")'].browser_download_url | [0]")"
[ "$url" != null ] || fail "the zip is not on release $id"
back="$(curl -fsSL --max-time 120 "$url" | shasum -a 256 | cut -d' ' -f1)"
[ "$back" = "$sum" ] || fail "downloaded checksum $back does not match $sum"
echo "released $tag, asset read back and matched: $url"
