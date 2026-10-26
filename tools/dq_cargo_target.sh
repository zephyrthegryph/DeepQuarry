#!/usr/bin/env bash
# Prints the cargo target directory a gate, push, prebuild or equivalence run must build into instead of <worktree>/tools/*/target:
#   export CARGO_TARGET_DIR="$(bash tools/dq_cargo_target.sh <name>)"
# It lives under the disposable cache root (E:/dq-cache/cargo-targets/<worktree>/<name>, else ~/.cache/dq/cargo-targets), one per worktree and
# name (cargo's fingerprints are path-relative, so two checkouts must not share one), and tools/dq_disk_budget.sh caps it
# (tools/ci/disk_budget.toml [cache.cargo-targets]: 6 GB per worktree directory, 18 GB for all, a leased slot's own target spared). Nothing is created here.
set -u
name="${1:?usage: dq_cargo_target.sh <name>}"
if [ -n "${DQ_CARGO_TARGETS:-}" ]; then root="$DQ_CARGO_TARGETS"
elif [ -d E:/dq-cache ]; then root="E:/dq-cache/cargo-targets"
else root="$HOME/.cache/dq/cargo-targets"; fi
wt="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"
echo "$root/$wt/$name"
