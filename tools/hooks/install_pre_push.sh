#!/usr/bin/env bash
# Installs tools/hooks/pre-push into the repository's shared hooks directory (all worktrees use it), replacing an older copy.
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
hooks="$(git rev-parse --git-common-dir)/hooks"
mkdir -p "$hooks"
cp "$root/tools/hooks/pre-push" "$hooks/pre-push"
chmod +x "$hooks/pre-push"
echo "installed $hooks/pre-push"
# The merge-lock guard: refuses updates of rewrite/integ-current inside the merge worktree without the merge lock.
# This hook is ours alone (never a user hook), so a reinstall replaces an older copy: the graceful-degradation fix reaches every worktree.
cp "$root/tools/hooks/reference-transaction" "$hooks/reference-transaction"
chmod +x "$hooks/reference-transaction"
echo "installed $hooks/reference-transaction"
