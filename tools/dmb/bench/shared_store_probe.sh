#!/usr/bin/env bash
# Memory probe for the shared store (lane compiler/shared-store). Runs ONE private daemon (namespace $NS) with the
# counting build and compiles the given roots in order through it, with retention policies that never shed a session,
# then writes one `retained.after_request` block per request to $SITES (summarise with alloc_sites_by_owner.py).
#
#   shared_store_probe.sh <dmbc built with --features allocation-sites> <scratch dir> <root[:define,define]>...
#
# Each root is a directory holding deepquarry.dme; `|define` adds -D flags (the test world is
# `<root>|CIBUILDING,CITESTING`). Output: <scratch>/probe-<n>.log per request and <scratch>/sites.txt.
set -u
EXE=$1; SCRATCH=$2; shift 2
export DMB_DAEMON_NAMESPACE=${DMB_DAEMON_NAMESPACE:-sharedstore-probe}
export DMB_ALLOC_SITES_PATH=$SCRATCH/sites.txt
export DMB_DAEMON_ADAPTIVE=0 DMB_DAEMON_MEMORY_BUDGET_GB=48
export DMB_DAEMON_SOFT_PRIVATE_BYTES=34359738368 DMB_DAEMON_HARD_PRIVATE_BYTES=34359738368
mkdir -p "$SCRATCH"; : > "$DMB_ALLOC_SITES_PATH"
n=0
for spec in "$@"; do
  root=${spec%%|*}; defs=""
  if [ "$spec" != "$root" ]; then for d in $(echo "${spec#*|}" | tr ',' ' '); do defs="$defs -D$d"; done; fi
  n=$((n+1))
  ( cd "$root" && "$EXE" compile deepquarry.dme --progress --workers 4 --output-store "$SCRATCH/store" $defs > "$SCRATCH/probe-$n.log" 2>&1; echo "exit $?" >> "$SCRATCH/probe-$n.log" )
  grep -h "native compile: .*session=" "$SCRATCH/probe-$n.log" | cut -c1-300
  # The daemon writes the sites report from housekeeping once idle; wait for this request's block.
  for _ in $(seq 1 60); do [ "$(grep -c '^######## retained.after_request' "$DMB_ALLOC_SITES_PATH")" -ge "$n" ] && break; sleep 2; done
done
DMB_DAEMON_AUTOSTART=0 "$EXE" --daemon-retire > /dev/null 2>&1 || true
