# Install and release

How `SSM.app` reaches a Mac, and what is still open.

## What the cask does

`Casks/ssm.rb` in `coilyco/homebrew-tap` downloads `SSM-<version>-arm64.zip` from the GitHub release of this repo, checks its sha256, and installs `SSM.app` into the Homebrew appdir. It then clears `com.apple.quarantine` on the installed bundle.

- **Why GitHub.** Forgejo is tailnet-only, so brew cannot fetch from it anonymously. The fleet mirror timer copies Forgejo release assets to GitHub, as it does for `aos`.
- **Why the quarantine step.** The bundle is ad-hoc signed and not notarized, so Gatekeeper would refuse a quarantined copy. Notarizing needs an Apple Developer ID, which this repo does not have.
- **Why arm64 only.** SwiftPM builds the host architecture with Command Line Tools alone, and a universal build needs Xcode.
- **Appdir.** A cask `app` stanza installs into the Homebrew appdir. Landing in `~/Applications` is a per-host setting, `HOMEBREW_CASK_OPTS=--appdir=$HOME/Applications`, converged by ansible and never by the cask.

## Cutting a release

A release is cut by hand on a Mac, because no Forgejo runner carries a macOS label and AppKit does not build on the Linux ones. Kai chose this over a macOS runner or GitHub Actions.

1. From a clean checkout at `origin/main`, run `just release x.y.z`. It builds and zips the app, creates the Forgejo release `vx.y.z` at that commit, uploads the zip and its sha256, and reads the zip back through its public URL to compare the checksum. `--dry-run` stops after the build.
2. The fleet mirror copies the release assets to GitHub, which is where the cask points.
3. Run `just tap-cask x.y.z` to open the `homebrew-tap` pull request that points `Casks/ssm.rb` at the release, then merge it.

A mirrored asset is never overwritten, so the verb refuses a tag whose release already has assets. A release left with none by an interrupted run, at the same commit, is finished instead. Cut a new version to redo one.

## Descriptions

The app reads and writes the SSM Description field, up to 1024 characters. A description edit on an existing parameter re-puts its value, which writes a new version.
