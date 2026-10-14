#!/bin/bash
# The grep-style code and map checks (map issues, banned patterns, ratchet counts, indentation,
# changelog pin, HTML tag matching, ...): formerly ~70 rg/grep pipelines run one after another
# (about 2.5 minutes), now the `check_grep` lint of the analyze engine (tools/analyze, README there:
# `check_grep` section), which reads the tree once and runs every part in parallel. Same checks, same
# exit status (non-zero when any part finds something); `file:line: [check_grep/<part>] text` per hit.
# This wrapper keeps the script's name for CI and muscle memory.
set -euo pipefail
cd "$(dirname "$0")/../.."
bin="$(bash tools/ci/analyze.sh)"
exec "$bin" check --lint check_grep --ci "$@"
