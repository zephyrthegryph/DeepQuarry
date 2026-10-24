#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

bash ../tools/ci/gen_verdigris_bindings.sh
cargo build --release --target i686-unknown-linux-gnu
cp "target/i686-unknown-linux-gnu/release/libverdigris.so" "../libverdigris.so"
