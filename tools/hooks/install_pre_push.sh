#!/usr/bin/env bash
# Installs tools/hooks/pre-push into the repository's shared hooks directory (all worktrees use it), replacing an older copy.
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
hooks="$(git rev-parse --git-common-dir)/hooks"
mkdir -p "$hooks"
cp "$root/tools/hooks/pre-push" "$hooks/pre-push"
chmod +x "$hooks/pre-push"
echo "installed $hooks/pre-push"
