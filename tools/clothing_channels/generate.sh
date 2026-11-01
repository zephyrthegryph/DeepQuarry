#!/usr/bin/env bash
# Regenerates strings/clothing_channels/generated.json from the analyzer's view of the tree. See generate.py.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
out=E:/dq-cache/clothing-channels/out
mkdir -p "$out"
bin=tools/analyze/target/dev-fast/analyze
[ -x "$bin" ] || [ -x "$bin.exe" ] || cargo build --profile dev-fast --manifest-path tools/analyze/Cargo.toml
"$bin" sem clothing-dump > "$out/dump.jsonl"
# Needs numpy, scipy, Pillow and Python 3.11+ (tomllib). CLOTHING_CHANNELS_PYTHON picks the interpreter.
exec "${CLOTHING_CHANNELS_PYTHON:-python}" tools/clothing_channels/generate.py --repo . --dump "$out/dump.jsonl" --out "$out" "$@"
