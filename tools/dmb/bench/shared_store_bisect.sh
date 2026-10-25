#!/usr/bin/env bash
# Bisect a difference between a shared-daemon output and its cold reference (lane compiler/shared-store).
#
#   shared_store_bisect.sh <dmbc> <scratch dir> <root> <expected pair id of the test flavour> [private owners]
#
# Runs, in one fresh daemon with sharing on and `DMB_SHARED_STORE_PRIVATE=<private owners>`, the game flavour and then the
# test flavour of <root> and prints the test flavour's pair id and whether it equals the expected one. The expected id comes
# from a cold compile (shared_store_equiv.sh prints it as the reference). Owners are core names or prefixes, `records`, `pools`
# and `proofs` (see tools/dmb/crates/dmbc/src/shared_store.rs).
set -u
EXE=$1; S=$2; ROOT=$3; EXPECT=$4; PRIV=${5:-}
mkdir -p "$S"; rm -rf "$S/store"
export DMB_DAEMON_NAMESPACE=sharedstore-bisect DMB_SHARED_STORE=1 DMB_SHARED_STORE_PRIVATE=$PRIV DMB_DAEMON_ADAPTIVE=0
export DMB_DAEMON_MEMORY_BUDGET_GB=48 DMB_DAEMON_SOFT_PRIVATE_BYTES=34359738368 DMB_DAEMON_HARD_PRIVATE_BYTES=34359738368
( cd "$ROOT" && "$EXE" compile deepquarry.dme --progress --workers 4 --output-store "$S/store" > "$S/game.log" 2>&1 )
( cd "$ROOT" && "$EXE" compile deepquarry.dme --progress --workers 4 --output-store "$S/store" -DCBT -DCIBUILDING -DCITESTING -DDEBUG > "$S/test.log" 2>&1 )
[ -n "${DMB_MEM_MARKS:-}" ] && sleep 45 # housekeeping logs the store report after the request
DMB_DAEMON_AUTOSTART=0 "$EXE" --daemon-retire > /dev/null 2>&1 || true
pair=$(grep -ho "pair=[0-9a-f]\{32\}" "$S/test.log" | head -1 | sed 's/pair=//')
if [ "$pair" = "$EXPECT" ]; then echo "SAME   private=[$PRIV] test pair $pair"; else echo "DIFFER private=[$PRIV] test pair $pair (expected $EXPECT)"; fi
sleep 3
