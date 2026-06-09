#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

cargo build --release --target i686-pc-windows-msvc
cp "target/i686-pc-windows-msvc/release/verdigris.dll" "../verdigris.dll"
