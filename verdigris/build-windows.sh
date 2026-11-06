#!/bin/bash
set -euo pipefail
# Below normal priority, for this script and everything it starts (cargo and rustc, the analyzer, git): the machine is also the user's desktop.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../tools/dq_below_normal.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

bash ../tools/ci/gen_verdigris_bindings.sh
cargo build --release --target i686-pc-windows-msvc
cp "target/i686-pc-windows-msvc/release/verdigris.dll" "../verdigris.dll"
