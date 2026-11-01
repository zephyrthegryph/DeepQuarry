#!/usr/bin/env bash
# dq_push_master.sh refuses an unstamped commit before the compile and the ratchets, whose results cannot change the stamp's verdict.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
f=tools/dq_push_master.sh
refuse="$(grep -n 'stamp_of "$sha" >/dev/null; \[ "$_stamp_rc" -eq 0 \] || die "$_stamp_out"' "$f" | head -n 1 | cut -d: -f1)"
reproof="$(grep -n 're-proof passed: HEAD is now' "$f" | cut -d: -f1)"
dm="$(grep -n '== build.sh dm on ' "$f" | cut -d: -f1)"
fail=0
if [ -n "$refuse" ] && [ "$refuse" -gt "$reproof" ] && [ "$refuse" -lt "$dm" ]; then echo "PASS: the refusal sits after the re-proof and before the build"; else echo "FAIL: refuse=$refuse reproof=$reproof dm=$dm"; fail=1; fi
[ "$fail" -eq 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
