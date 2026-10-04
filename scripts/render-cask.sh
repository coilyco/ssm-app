#!/usr/bin/env bash
# Render the cask for one release. Usage: render-cask.sh <version> <sha256> <out>
# The url names GitHub, where the mirror copies release assets.
set -euo pipefail

version="${1:?version}"
sha256="${2:?sha256}"
out="${3:?output file}"

cat > "$out" <<CASK
cask "ssm" do
  version "${version}"
  sha256 "${sha256}"

  url "https://github.com/coilyco/ssm-app/releases/download/v#{version}/SSM-#{version}-arm64.zip"
  name "SSM"
  desc "Native app for AWS SSM Parameter Store"
  homepage "https://github.com/coilyco/ssm-app"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "SSM.app"

  # Ad-hoc signed and not notarized, so Gatekeeper needs the quarantine flag cleared.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/SSM.app"]
  end

  zap trash: "~/Library/Preferences/me.coilysiren.ssm.plist"
end
CASK
