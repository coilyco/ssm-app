---
ward:
  workflow: pull-request-and-merge
---
# Agent instructions

Workspace conventions load globally via `~/.claude/CLAUDE.md`. This file covers only what is specific to **ssm-app**.

## Scope

A native macOS app for AWS SSM Parameter Store: list, read, write, rotate, and delete parameters under the caller's own AWS profile. It ships to Macs as the `ssm` Homebrew cask in `coilyco/homebrew-tap`.

## Project shape

- `Sources/SsmCore` - the aws CLI wrapper, name and secret rules, and the optional descriptions overlay parser. No UI, so the checks can drive it.
- `Sources/SsmApp` - the SwiftUI app and its model. `SSM_APP_DRIVE=1` runs the model flows headless against whatever aws it is pointed at.
- `Sources/SsmCheck` - the check executable and the fake aws every check runs against. Nothing in this repo reaches AWS.
- `scripts/` - `package.sh` zips a release build, `release.sh` cuts a release by hand, `render-cask.sh` and `tap-cask.sh` render and propose the cask.
- [docs/release.md](docs/release.md) - how it installs, how a release is cut, and the signing caveat.

## Repo boundaries

Public on Forgejo and its GitHub mirror, so no parameter name, account id, host, or description from a real account belongs in any tracked file. Descriptions live in SSM's own Description field. The aosk yaml overlay is opt-in through `SSM_APP_REPO` or the `descriptionsRepo` preference, and the app never bundles an index.

## Commands

Route dev commands through the [`justfile`](justfile). Bare `just` lists every verb: `build`, `check`, `package`, `release`, `tap-cask`, `ci`. Add a verb there before invoking it.

## Validation

`just check` runs the core checks and the model driver twice, with the overlay and without. Run `pre-commit run --all-files` before committing. The Linux CI runner cannot build AppKit, so CI runs the pre-commit suite only and `just check` is run on a Mac.

## Safety

A value reaches the aws CLI on stdin and never argv, a log, or a file. One trailing newline is stripped and every write is read back. Never put a secret in a description. Keep the repo free of real account data, since trufflehog is the backstop and not the discipline.

## Cross-repo contracts

The cask lives in `coilyco/homebrew-tap` and names this repo's GitHub release assets. The fleet mirror timer in infrastructure copies them across, and the per-host appdir is converged by ansible there.

## Release

Land work through the lane below. Reference the tracker record in the commit body, and close the record yourself. Voice rules apply (no em-dashes, no semicolons in prose).

## Agent rules

<!-- BEGIN managed by agentic-os/scripts/apply-git-workflow.py -->
### Git workflow

**This repo runs the `pull-request-and-merge` lane**, declared as `ward.workflow` in this file's frontmatter. The agent commits to a task branch, pushes it, opens a Forgejo pull request, and **merges that pull request itself** once it is green. The author of the code is the one who merges it. Opening the pull request is a step, never the stopping point.

The fleet runs one lane, and it authorizes the agent end to end. Pushing straight to `main` is over: `merge-remote-main` is retired, so no repo can declare its way back to one.

* `pull-request-and-merge` - the agent commits to a task branch, pushes it, opens a pull request, and merges that pull request itself once it is green.

**Every lane slug names what the AGENT does, never what someone else does.** `pull-request-and-merge` carries the merge because the agent that authored the code merges its own pull request. `pull-request` drops `-and-merge` because the author stops at the pull request and the director merge lane takes over. Reading `pull-request-and-merge` as "someone else merges it later" inverts the two and leaves finished work sitting unmerged.

**These actions are pre-authorized on every lane, and the agent MUST take them without asking first.** Committing, creating a branch, pushing a branch, pushing the lane's own destination, and opening a pull request are ordinary reversible work, not the destructive wall that earns a question. Stopping to ask is how a turn ends with the work stranded in a dirty worktree.

* **ALWAYS commit** in-scope work and **ALWAYS push** it to the canonical remote before pausing, reporting a checkpoint, handing off, or ending a turn. A local-only commit is not a checkpoint.
* **ALWAYS open the pull request** in the same turn as the branch's first push, on every lane except `remote-branch-only`. A pushed branch with no pull request is litter nobody reviews.
* **NEVER `--no-verify`** and **NEVER force-push**. Those two are the real walls, and they stay closed.
* **ALWAYS merge your own pull request on `pull-request-and-merge`**, in the same turn, as soon as it is green. Reporting it as open and awaiting someone is the failure this lane exists to prevent.
* **A merge refused with 405 "the head branch is behind the base branch" is yours to fix, never a reason to ask.** Update the branch yourself, with `aosguard ops forgejo pr update <owner> <repo> <index>`, the forgejo `update_pull-request` verb, or by merging `origin/main` into it and pushing, never by force. Wait for green, then merge.
* **NEVER merge on `pull-request` or `remote-branch-only`.** Those two stop where they stop, and the director merge lane carries a `pull-request` from there.
<!-- END managed by agentic-os/scripts/apply-git-workflow.py -->

## See also

- [README.md](README.md) - what this is and how to install it.
- [docs/FEATURES.md](docs/FEATURES.md) - inventory of what ships today.
