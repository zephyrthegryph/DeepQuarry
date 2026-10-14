#!/bin/bash
# Provision a Claude Code on the web container for building and testing
# DeepQuarry on Linux: BYOND, 32-bit toolchain, rust-g, the i686 Rust target
# (verdigris), SpacemanDMM, Python tooling and JS deps.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "$CLAUDE_PROJECT_DIR"
export DEBIAN_FRONTEND=noninteractive

# 32-bit libs for DreamDaemon, rust-g and the i686 verdigris build.
if ! dpkg -s zlib1g-dev:i386 libssl-dev:i386 libcurl4t64:i386 gcc-multilib >/dev/null 2>&1; then
  dpkg --add-architecture i386
  apt-get update -qq || true
  apt-get install -y -qq -o APT::Immediate-Configure=false \
    gcc-multilib zlib1g-dev:i386 libssl-dev:i386 libstdc++6:i386 libcurl4t64:i386 unzip
fi

# BYOND (cached by version), rust-g, SpacemanDMM.
bash tools/ci/install_byond.sh
[ -f "$HOME/.byond/bin/librust_g.so" ] || bash tools/ci/install_rust_g.sh
bash tools/ci/install_spaceman_dmm.sh dreamchecker >/dev/null

# verdigris targets i686. Test/bench worlds boot from data/runs/runN, so
# DreamDaemon finds the library through ~/.byond/bin (like rust-g); link the
# repo copy the build writes there.
rustup target add i686-unknown-linux-gnu >/dev/null 2>&1 || true
ln -sf "$CLAUDE_PROJECT_DIR/libverdigris.so" "$HOME/.byond/bin/libverdigris.so"

# Python tooling (icon repack, changelogs, lints).
pip install -q Pillow PyYaml beautifulsoup4 2>&1 | grep -v "root user" || true

# JS deps (build orchestration + tgui).
bun install >/dev/null
(cd tgui && bun install >/dev/null)

# BYOND on PATH for the session. Test worlds run from data/runs/runN, and
# -safe blocks the libraries in ~/.byond/bin; Linux DreamDaemon has no
# trusted-mode dialog, so run trusted.
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "source \$HOME/BYOND/byond/bin/byondsetup" >> "$CLAUDE_ENV_FILE"
  echo "export DQ_DD_SECURITY=trusted" >> "$CLAUDE_ENV_FILE"
fi
