#!/usr/bin/env bash
# Equivalence and isolation proof for the shared store (lane compiler/shared-store).
#
#   shared_store_equiv.sh <dmbc> <dmb-equiv> <scratch dir> <rootA> <rootB> [run id]
#
# rootA and rootB are two copies of one tree (a directory holding deepquarry.dme each). The script
#  1. appends a marker proc to one file of each root (MARKER-A-<id> / MARKER-B-<id>), so an edit in one root that leaked into
#     the other root's output would be visible in its bytes;
#  2. compiles each (root, flavour) from cold in its own private daemon with sharing off (DMB_SHARED_STORE=0): the reference;
#  3. compiles the same list interleaved A-game, B-game, A-test, B-test, B-game, A-game through ONE daemon with sharing on;
#  4. requires every shared-daemon output to carry the reference pair id, be byte-identical (.dmb and .rsc), be
#     `dmb-equiv --all --ignore-debug` EQUIVALENT, and the other root's marker to be absent from its bytes.
# Flavours: game = deepquarry.dme; test = -DCBT -DCIBUILDING -DCITESTING -DDEBUG (the unit-test world).
# Exit status 0 only when every check holds. Everything lives under <scratch dir>.
set -u
EXE=$1; EQUIV=$2; S=$3; A=$4; B=$5; ID=${6:-$$}
TESTDEFS="-DCBT -DCIBUILDING -DCITESTING -DDEBUG"
mkdir -p "$S"; fail=0
marker() { # <root> <label>
  f="$1/code/game/objects/items/falling_object.dm"
  sed -i '/^\/proc\/dq_shared_store_marker/,$d' "$f"
  printf '/proc/dq_shared_store_marker()\n\treturn "MARKER-%s-%s"\n' "$2" "$ID" >> "$f"
}
marker "$A" A; marker "$B" B
daemon_env() { # <namespace> <sharing 0|1>
  export DMB_DAEMON_NAMESPACE=$1 DMB_SHARED_STORE=$2 DMB_DAEMON_ADAPTIVE=0 DMB_DAEMON_MEMORY_BUDGET_GB=48
  export DMB_DAEMON_SOFT_PRIVATE_BYTES=34359738368 DMB_DAEMON_HARD_PRIVATE_BYTES=34359738368
}
PHASE=ref
build() { # <root> <flavour> <tag>: compile in the current daemon, keep the outputs as <S>/<tag>.{dmb,rsc,log}
  # Each phase has its own pair store, so no stored session record of the reference answers the shared run: it really compiles.
  defs=""; [ "$2" = test ] && defs=$TESTDEFS
  ( cd "$1" && "$EXE" compile deepquarry.dme --progress --workers 4 --output-store "$S/store-$PHASE" $defs > "$S/$3.log" 2>&1; echo "exit $?" >> "$S/$3.log" )
  cp "$1/deepquarry.dmb" "$S/$3.dmb" 2>/dev/null; cp "$1/deepquarry.rsc" "$S/$3.rsc" 2>/dev/null
  echo "$(pair "$3") ($3: $(grep -h 'native compile: ' "$S/$3.log" | grep -v 'native compile: total' | sed 's/ workers.*//' | tr -d '\n'))"
}
retire() { DMB_DAEMON_AUTOSTART=0 "$EXE" --daemon-retire > /dev/null 2>&1 || true; sleep 3; }
pair() { grep -ho "pair=[0-9a-f]\{32\}" "$S/$1.log" | head -1 | sed 's/pair=//'; }

echo "== reference: cold, private daemon each, sharing off"
for spec in ${REF_ROOTS:-"A:$A" "B:$B"}; do
  for flavour in game test; do
    daemon_env "sharedstore-ref" 0
    build "${spec#*:}" $flavour "ref-${spec%%:*}-$flavour"; retire
  done
done

echo "== shared daemon, sharing on, interleaved"
mkdir -p "$S/store-shared"; PHASE=shared
daemon_env "sharedstore-equiv" "${SHARING:-1}"
n=0
if [ -z "${STEP_LIST:-}" ]; then STEPS=("A game" "B game" "A test" "B test" "B game" "A game"); else IFS=';' read -r -a STEPS <<< "$STEP_LIST"; fi
for step in "${STEPS[@]}"; do
  set -- $step; n=$((n+1)); root=$A; [ "$1" = B ] && root=$B
  tag="shared-$n-$1-$2"; build "$root" "$2" "$tag"
  ref="ref-$1-$2"; other=B; [ "$1" = B ] && other=A
  ok=1
  [ -s "$S/$tag.dmb" ] || { echo "FAIL $tag: no output"; ok=0; }
  [ "$(pair $tag)" = "$(pair $ref)" ] || { echo "FAIL $tag: pair id $(pair $tag) != reference $(pair $ref)"; ok=0; }
  cmp -s "$S/$tag.dmb" "$S/$ref.dmb" || { echo "NOTE $tag: .dmb not byte-identical to reference"; }
  cmp -s "$S/$tag.rsc" "$S/$ref.rsc" || { echo "NOTE $tag: .rsc not byte-identical to reference"; }
  "$EQUIV" "$S/$ref.dmb" "$S/$tag.dmb" --rsc "$S/$ref.rsc" "$S/$tag.rsc" --all --ignore-debug --quiet > "$S/$tag.equiv.txt" 2>&1 \
    || { echo "FAIL $tag: dmb-equiv reports a difference (see $tag.equiv.txt)"; ok=0; }
  "$EQUIV" dump-proc "$S/$tag.dmb" dq_shared_store_marker > "$S/$tag.marker.txt" 2>&1
  if grep -q "MARKER-$other-" "$S/$tag.marker.txt"; then echo "FAIL $tag: leaked MARKER-$other"; ok=0; fi
  grep -q "MARKER-$1-$ID" "$S/$tag.marker.txt" || { echo "FAIL $tag: own marker missing"; ok=0; }
  [ $ok = 1 ] && echo "ok   $tag (pair $(pair $tag))" || fail=1
done
retire
[ $fail = 0 ] && echo "EQUIVALENT: all shared-daemon outputs match their cold references" || echo "NOT EQUIVALENT"
exit $fail
