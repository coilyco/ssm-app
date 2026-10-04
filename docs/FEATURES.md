# Features

What ssm-app ships today.

- **SSM Parameter Store window** - lists parameters grouped by path, searches names and descriptions, and reveals, writes, rotates, and deletes under the caller's own AWS profile. Values travel on stdin only, a trailing newline is stripped, and every write is read back. See the [README](../README.md).
- **Descriptions in SSM** - a parameter's description is its own SSM Description field, with an opt-in yaml overlay for a checkout that keeps an index.
- **Homebrew cask** - installs as `coilyco/tap/ssm` from a GitHub release asset. See [release](release.md).

## See also

- [README.md](../README.md) - what this is and how to install it.
- [AGENTS.md](../AGENTS.md) - repo-local operating rules.
