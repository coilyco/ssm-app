# Dev verbs for ssm-app. Run `just` to list them.

set positional-arguments

# Default target: list every available recipe.
default:
    @just --list --unsorted

# Build SSM.app from the Swift package and open it, pass --no-open to skip the launch.
build *ARGS:
    @bash build-app.sh "$@"

# Run the core checks and the model driver against a fake aws, with and without the overlay.
check *ARGS:
    @bash check.sh "$@"

# Build and zip a release, set VERSION=x.y.z, writes dist/SSM-<version>-<arch>.zip and its sha256.
package:
    @bash scripts/package.sh

# Cut a release by hand on a Mac, pass x.y.z and optionally --dry-run, and see docs/release.md.
release *ARGS:
    @bash scripts/release.sh "$@"

# Open the homebrew-tap pull request that points the ssm cask at a released x.y.z.
tap-cask VERSION:
    @bash scripts/tap-cask.sh "{{VERSION}}"

# Run the full pre-commit suite, which is what CI runs.
ci:
    @pre-commit run --all-files
