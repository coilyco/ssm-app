# Install and release

How `SSM.app` reaches a Mac, and what is still open.

## What the cask does

`Casks/ssm.rb` in `coilyco/homebrew-tap` downloads `SSM-<version>-arm64.zip` from the GitHub release of this repo, checks its sha256, and installs `SSM.app` into the Homebrew appdir. It then clears `com.apple.quarantine` on the installed bundle.

- **Why GitHub.** Forgejo is tailnet-only, so brew cannot fetch from it anonymously. The fleet mirror timer copies Forgejo release assets to GitHub, as it does for `aos`.
- **Why the quarantine step.** The bundle is ad-hoc signed and not notarized, so Gatekeeper would refuse a quarantined copy. Notarizing needs an Apple Developer ID, which this repo does not have.
- **Why arm64 only.** SwiftPM builds the host architecture with Command Line Tools alone, and a universal build needs Xcode.
- **Appdir.** A cask `app` stanza installs into the Homebrew appdir. Landing in `~/Applications` is a per-host setting, `HOMEBREW_CASK_OPTS=--appdir=$HOME/Applications`, converged by ansible and never by the cask.

## Cutting a release

`scripts/package.sh` builds with `VERSION` set and writes the zip and its sha256. `scripts/render-cask.sh` renders the cask for that version and checksum. Both need macOS, because AppKit does not build on the Linux Forgejo runners.

The release train that runs them on a push is not wired yet, because no Forgejo runner carries a macOS label. Until one does, a release is cut by hand on a Mac, which is the gap this page tracks.

## Descriptions

The app reads and writes the SSM Description field, up to 1024 characters. A description edit on an existing parameter re-puts its value, which writes a new version.
