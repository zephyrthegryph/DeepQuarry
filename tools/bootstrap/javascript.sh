#!/bin/sh
# bootstrap/bun
#
# Bun-finding script for all `sh` environments, including Linux, MSYS2,
# Git for Windows, and GitHub Desktop. Invokable from CLI or automation.
#
# If a bun executable installed by a bootstrapper is present, it will be used.
# Otherwise, this script requires a system `bun` to be provided.
set -e

# Load Bun version from dependencies.sh
OldPWD="$PWD"
cd "$(dirname "$0")/../.."
. ./dependencies.sh  # sets BUN_VERSION (define this in dependencies.sh)
cd "$OldPWD"
BunVersion="$BUN_VERSION"
BunFullVersion="bun-v$BunVersion"

# Check if symlinks are supported in this directory
test_symlink_support() {
    echo "Testing symlink support."
    TMPDIR=$(mktemp -d)
    TARGET="$TMPDIR/target.txt"
    LINK="$TMPDIR/link.txt"
    echo "test" > "$TARGET"
    if ln -s "$TARGET" "$LINK" 2>/dev/null; then
        rm -rf "$TMPDIR"
        echo "Symlinks are supported."
        return 0
    else
        rm -rf "$TMPDIR"
        echo "File system does not support symlinks. Compilation won't be possible."
        exit 1
    fi
}

# The probe costs several process spawns on Windows and its answer does not change for a checkout:
# a marker under the gitignored data/ skips it after the first pass.
SymlinkMarker="$(dirname "$0")/../../data/.symlink_ok"
if [ ! -f "$SymlinkMarker" ]; then
    test_symlink_support
    mkdir -p "$(dirname "$SymlinkMarker")" 2>/dev/null && : > "$SymlinkMarker" 2>/dev/null || true
fi

# If Bun is not present, install using the official installer.
if ! command -v bun >/dev/null 2>&1; then
    echo "Bun not found, installing with official installer..."
    curl -fsSL https://bun.sh/install | bash -s $BunFullVersion
    if [ -d "$HOME/.bun/bin" ]; then
        export PATH="$HOME/.bun/bin:$PATH"
    else
        echo "Bun installation directory not found. Please check the installation."
        exit 1
    fi
fi

echo "Using Bun (pinned $BunVersion)"
# Shared transpiler cache can resolve across identical worktrees; keep it off.
export BUN_RUNTIME_TRANSPILER_CACHE_PATH=0
exec bun "$@"
