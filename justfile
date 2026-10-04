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

# Run the full pre-commit suite, which is what CI runs.
ci:
    @pre-commit run --all-files
