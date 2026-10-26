#!/usr/bin/env bash
# The cache prune is the disk budget now: tools/dq_disk_budget.sh enforces tools/ci/disk_budget.toml (a size cap, an age cap and an eviction policy for
# every directory under E:/dq-cache and every per-worktree growth dir, a total cap, the disk floor). Kept as the old entry point:
#
#   bash tools/dq_cache_prune.sh [--dry-run]
exec bash "$(dirname "${BASH_SOURCE[0]}")/dq_disk_budget.sh" enforce --force "$@"
