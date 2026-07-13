#!/bin/sh

#Project dependencies file
#Final authority on what's required to fully build the project

# byond version
# 516.1682 is the minimum: it introduced the modern byondapi ABI (buffer-based
# Byond_LastError + DecTempRef reference handling) that the Rust atmos library
# (verdigris/auxmos, byondapi 0.6.x, feature byond-516-1682) links against. On
# 516.1681 or earlier, DreamDaemon crashes at atmos init with "undefined symbol:
# ByondValue_DecTempRef". Do not downgrade below 1682.
export BYOND_MAJOR=516
export BYOND_MINOR=1682

# Macro Count
export MACRO_COUNT=7

#rust_g git tag
export RUST_G_VERSION=6.1.0

# verdigris is the in-tree rust extension (built from source); toolchain is pinned in verdigris/rust-toolchain.toml
# Targets: i686-unknown-linux-gnu (libverdigris.so) and i686-pc-windows-msvc (verdigris.dll)

# node version
export NODE_VERSION_LTS=22.14.0

# Bun version
export BUN_VERSION=1.3.14

# SpacemanDMM git tag
export SPACEMAN_DMM_VERSION=suite-1.11

# Python version for mapmerge and other tools
export PYTHON_VERSION=3.12.3

#dreamluau repo
export DREAMLUAU_REPO="tgstation/dreamluau"

#dreamluau git tag
export DREAMLUAU_VERSION=0.1.4
