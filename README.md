# ssm-app

A native macOS app for AWS SSM Parameter Store. It lists every parameter in a window, shows each one's type, version, and description, reveals a value on demand, and writes, rotates, and deletes under your own AWS profile.

## Install

```sh
brew tap coilyco/tap
brew install --cask coilyco/tap/ssm
```

The cask installs `SSM.app` into your Applications directory. To put it in `~/Applications`, install with `HOMEBREW_CASK_OPTS="--appdir=$HOME/Applications"`. The app shells out to the `aws` CLI, so `brew install awscli` and sign in with your own profile first.

The bundle is ad-hoc signed and not notarized. The cask clears the download quarantine flag after install, which is what lets it open. See [docs/release.md](docs/release.md).

## Descriptions

A parameter's description is SSM's own Description field, so it follows the parameter. Leaving the field empty on a replace keeps the one already there.

## Build and check

```sh
just build     # build SSM.app and open it
just check     # core checks plus the model driver, against a fake aws
just package   # VERSION=x.y.z, writes dist/SSM-<version>-<arch>.zip
```

Needs a Mac with Swift (Command Line Tools are enough) and macOS 14 or later. Nothing here reaches AWS.

## Licence

MIT, see [LICENSE](LICENSE).

## See also

- [AGENTS.md](AGENTS.md) - repo-local operating rules.
- [docs/FEATURES.md](docs/FEATURES.md) - inventory of what ships today.
