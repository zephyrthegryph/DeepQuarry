#!/usr/bin/env bash
# Installs tools/hooks/pre-push into the repository's shared hooks directory (all worktrees use it), so a push to
# master that did not come from tools/dq_push_master.sh is refused. Leaves an existing different hook alone.
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
hooks="$(git rev-parse --git-common-dir)/hooks"
mkdir -p "$hooks"
if [ -e "$hooks/pre-push" ] && ! cmp -s "$hooks/pre-push" "$root/tools/hooks/pre-push"; then
	echo "install_pre_push: $hooks/pre-push exists and differs; merge it by hand" >&2
	exit 1
fi
cp "$root/tools/hooks/pre-push" "$hooks/pre-push"
chmod +x "$hooks/pre-push"
echo "installed $hooks/pre-push"
