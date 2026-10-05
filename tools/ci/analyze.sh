#!/usr/bin/env bash
# Prints the path of the `analyze` lint engine binary (tools/analyze), building it first when stale
# (the shared binary cache, else cargo's own up-to-date check: a no-op, about a second, when nothing changed).
#
#   bin=$(bash tools/ci/analyze.sh) && "$bin" check --ci
#
# DQ_ANALYZE_PROFILE=debug builds the dev profile instead of release. DQ_ANALYZE_NO_BUILD=1 reuses an
# existing binary without asking cargo (a CI step that already built it). CARGO_TARGET_DIR is honoured.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
manifest="$root/tools/analyze/Cargo.toml"
profile="${DQ_ANALYZE_PROFILE:-release}"
exe="analyze"
case "$(uname -s 2>/dev/null || echo unknown)" in
	MINGW* | MSYS* | CYGWIN*) exe="analyze.exe" ;;
esac
target_dir="${CARGO_TARGET_DIR:-$root/tools/analyze/target}"
bin="$target_dir/$profile/$exe"
if [ -n "${DQ_ANALYZE_NO_BUILD:-}" ] && [ -x "$bin" ]; then
	echo "$bin"
	exit 0
fi
# The release binary goes through the build tool's analyze-build target: it restores the binary from the
# shared content-addressed cache (DQ_ANALYZE_CACHE, E:/dq-cache/analyze-bin) when another worktree already
# built these sources, and builds and stores it otherwise. A fresh worktree then needs no cargo build.
if [ "$profile" = "release" ] && [ -z "${DQ_ANALYZE_DIRECT_CARGO:-}" ]; then
	"$root/tools/build/build.sh" analyze-build >&2 || {
		echo "analyze: tools/build/build.sh analyze-build failed" >&2
		exit 1
	}
	if [ -x "$bin" ]; then
		echo "$bin"
		exit 0
	fi
fi
if ! command -v cargo >/dev/null 2>&1; then
	if [ -x "$bin" ]; then
		echo "$bin"
		exit 0
	fi
	echo "analyze: cargo not found and $bin is missing; install rustup (see verdigris/README.md)" >&2
	exit 1
fi
args=(build --quiet --manifest-path "$manifest")
if [ "$profile" = "release" ]; then
	args+=(--release)
fi
cargo "${args[@]}" >&2
echo "$bin"
