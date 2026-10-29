#!/usr/bin/env bash
# Proves tools/dq_disk_budget.sh on a temp tree (never the real cache): over-budget eviction oldest first, units in use kept (recently
# modified, leased slot, newest keep), an unknown directory removed, a file-level table and a per-worktree growth dir capped, the
# whole-cache total cap, and the disk floor refusing heavy work. Cargo targets are evicted ONLY as whole profile directories (never file by file),
# never in a permanent, leased or slot-holding worktree, never while recently modified.
set -uo pipefail
cd "$(dirname "$0")/../.."
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export DQ_CACHE_ROOT="$T/cache" DQ_WT_ROOT="$T/wt" DQ_DISK_MANIFEST="$T/m.toml" DQ_DISK_TOOLS=0 DQ_DISK_FREE_GB=500
mkdir -p "$DQ_CACHE_ROOT/lane-pool" "$DQ_CACHE_ROOT/logs" "$DQ_WT_ROOT"
cat >"$T/m.toml" <<'TOML'
[settings]
total_gb = 60
floor_gb = 50
aggressive_pct = 50
min_idle_min = 30
index_ttl_min = 0
permanent_worktrees = perm-wt
[cache.units]
policy = children-lru
cap_mb = 3
protect = leased-slot
[cache.logs]
policy = files-lru
depth = 2
cap_mb = 2
keep = 1
[cache.targets]
policy = cargo-units
cap_mb = 100
sub_cap_mb = 2
[cache.small]
policy = children-lru
cap_mb = 100
[cache.slots]
policy = state
[cache.lane-pool]
policy = state
[worktree.cargo]
path = tools/analyze/target
policy = cargo-units
cap_mb = 2
age_days = 7
[worktree.growth]
path = data/test-runs
policy = files-lru
cap_mb = 1
age_days = 3
TOML
mk() { head -c "$2" /dev/zero >"$1"; if [ -n "${3:-}" ]; then touch -d "$3" "$1"; fi; }   # mk <file> <bytes> [touch -d date]
unit() { mkdir -p "$1"; mk "$1/blob" 1048576; touch -d "$2" "$1/blob" "$1"; }
# children-lru: five 1 MB units against a 3 MB cap; the oldest unprotected goes, the leased one and the fresh one are spared
unit "$DQ_CACHE_ROOT/units/u1" "5 days ago"
unit "$DQ_CACHE_ROOT/units/pool-9" "6 days ago"; : >"$DQ_CACHE_ROOT/lane-pool/pool-9.lease"
unit "$DQ_CACHE_ROOT/units/u2" "4 days ago"
unit "$DQ_CACHE_ROOT/units/u3" "3 days ago"
unit "$DQ_CACHE_ROOT/units/fresh" "1 minute ago"
# cargo targets (cargo-units): a profile directory holds .fingerprint; `cprofile <dir> <days ago> <files> [oldest file days ago]` makes one of 1 MB files.
# The file times are set AFTER the directories, so a unit's age is the age of its newest file or directory.
cprofile() { local d="$1" i; mkdir -p "$d/.fingerprint/c" "$d/deps"; for i in $(seq 1 "$3"); do mk "$d/deps/d$i.rlib" 1048576 "$2"; done; mk "$d/.fingerprint/c/lib" 10 "$2"
	[ -n "${4:-}" ] && touch -d "$4" "$d/deps/d1.rlib"; touch -d "$2" "$d/deps" "$d/.fingerprint/c" "$d/.fingerprint" "$d"; }
for o in lane1 lane2 lane3 pool-8 perm-wt lane4; do mkdir -p "$DQ_CACHE_ROOT/targets/$o"; done
: >"$DQ_CACHE_ROOT/lane-pool/pool-8.lease"
# lane1: two idle profiles over the 2 MB per-owner cap: the least recently modified goes WHOLE, the other stays intact
cprofile "$DQ_CACHE_ROOT/targets/lane1/analyze-test/debug" "5 days ago" 3
cprofile "$DQ_CACHE_ROOT/targets/lane1/analyze-test/release" "4 days ago" 1
# lane2: over the cap, but in use (modified a minute ago) although its oldest file is days old: kept whole, the old file included
cprofile "$DQ_CACHE_ROOT/targets/lane2/t/debug" "1 minute ago" 4 "9 days ago"
# lane3: idle and over the cap, but it holds a machine slot right now
cprofile "$DQ_CACHE_ROOT/targets/lane3/t/debug" "6 days ago" 3
mkdir -p "$DQ_CACHE_ROOT/slots/cargo/slot.1"; printf 'kind=bash\npid=1\nworktree=E:/projects/dq-wt/lane3\n' >"$DQ_CACHE_ROOT/slots/cargo/slot.1/owner"
# a leased pool slot and a permanent worktree: idle and over the cap, never touched
cprofile "$DQ_CACHE_ROOT/targets/pool-8/t/debug" "6 days ago" 3
cprofile "$DQ_CACHE_ROOT/targets/perm-wt/t/debug" "6 days ago" 3
# lane4: nothing but leftovers, idle: the owner directory goes whole
mkdir -p "$DQ_CACHE_ROOT/targets/lane4/tmp"; mk "$DQ_CACHE_ROOT/targets/lane4/tmp/x" 100 "3 days ago"; touch -d "3 days ago" "$DQ_CACHE_ROOT/targets/lane4/tmp" "$DQ_CACHE_ROOT/targets/lane4"
# files-lru with keep: three 1 MB files against 2 MB; the oldest goes and the newest is kept
for i in 1 2 3; do mk "$DQ_CACHE_ROOT/logs/f$i.dat" 1048576 "$((i + 1)) days ago"; done
# unknown directory (old), unknown directory (busy), unknown stray file (old), a state dir
mkdir -p "$DQ_CACHE_ROOT/mystery" "$DQ_CACHE_ROOT/mystery-busy" "$DQ_CACHE_ROOT/slots" "$DQ_CACHE_ROOT/dmb-probe-old" "$DQ_CACHE_ROOT/train/queue" "$DQ_CACHE_ROOT/lane-pool/self"
mk "$DQ_CACHE_ROOT/dmb-probe-old/x" 2048 "3 days ago"; touch -d "3 days ago" "$DQ_CACHE_ROOT/dmb-probe-old"
mk "$DQ_CACHE_ROOT/train/queue/q1.q" 10 "30 days ago"; touch -d "30 days ago" "$DQ_CACHE_ROOT/train/queue" "$DQ_CACHE_ROOT/train"
mk "$DQ_CACHE_ROOT/lane-pool/self/x" 10 "30 days ago"; touch -d "30 days ago" "$DQ_CACHE_ROOT/lane-pool/self"
mk "$DQ_CACHE_ROOT/mystery/x" 2048 "3 days ago"; touch -d "3 days ago" "$DQ_CACHE_ROOT/mystery"
mk "$DQ_CACHE_ROOT/mystery-busy/x" 2048
mk "$DQ_CACHE_ROOT/slots/owner" 10 "9 days ago"
mk "$DQ_CACHE_ROOT/stray.log" 100 "2 days ago"
# an unknown stray cargo target (CACHEDIR.TAG): a cache by its own word, removed when idle
mkdir -p "$DQ_CACHE_ROOT/stray-target/debug"; mk "$DQ_CACHE_ROOT/stray-target/CACHEDIR.TAG" 40 "3 days ago"; mk "$DQ_CACHE_ROOT/stray-target/debug/x" 2048 "3 days ago"; touch -d "3 days ago" "$DQ_CACHE_ROOT/stray-target/debug" "$DQ_CACHE_ROOT/stray-target"
# a worktree growth dir: three 1 MB files, 1 MB cap, one past the 3 day age cap
mkdir -p "$DQ_WT_ROOT/lane-a/data/test-runs"; git init -q "$DQ_WT_ROOT/lane-a"
mk "$DQ_WT_ROOT/lane-a/data/test-runs/old.log" 1048576 "10 days ago"
mk "$DQ_WT_ROOT/lane-a/data/test-runs/mid.log" 1048576 "2 hours ago"
mk "$DQ_WT_ROOT/lane-a/data/test-runs/new.log" 1048576 "1 minute ago"
# a COMMITTED file in the growth dir, old and over the cap: git tracks it, so the enforcer must never delete it
mk "$DQ_WT_ROOT/lane-a/data/test-runs/tracked.log" 1048576 "20 days ago"
git -C "$DQ_WT_ROOT/lane-a" add -f data/test-runs/tracked.log && git -C "$DQ_WT_ROOT/lane-a" -c user.name=t -c user.email=t@t commit -q -m t
touch -d "20 days ago" "$DQ_WT_ROOT/lane-a/data/test-runs/tracked.log"

# a worktree own cargo target: an idle 3 MB profile over the 2 MB cap goes whole, the oldest file of a smaller fresh one never goes alone
cprofile "$DQ_WT_ROOT/lane-a/tools/analyze/target/debug" "5 days ago" 3
cprofile "$DQ_WT_ROOT/lane-a/tools/analyze/target/fresh" "1 minute ago" 1 "9 days ago"
mkdir -p "$DQ_WT_ROOT/perm-wt/tools/analyze/target"; git init -q "$DQ_WT_ROOT/perm-wt"; cprofile "$DQ_WT_ROOT/perm-wt/tools/analyze/target/debug" "9 days ago" 3

dry="$(bash tools/dq_disk_budget.sh enforce --dry-run 2>&1)"
check "dry run removes nothing" '[ -d "$DQ_CACHE_ROOT/units/u1" ] && [ -d "$DQ_CACHE_ROOT/mystery" ]'
check "dry run reports what it would remove" 'grep -q "would remove .*units/u1" <<<"$dry"'
check "dry run leaves every cargo profile alone" '[ -d "$DQ_CACHE_ROOT/targets/lane1/analyze-test/debug" ] && grep -q "would remove .*lane1/analyze-test/debug .*whole cargo profile" <<<"$dry"'

out="$(bash tools/dq_disk_budget.sh enforce 2>&1)"; echo "$out" | sed 's/^/     /'
check "over-budget: the oldest unprotected unit is evicted" '[ ! -d "$DQ_CACHE_ROOT/units/u1" ]'
check "over-budget: eviction stops once under the cap" '[ -d "$DQ_CACHE_ROOT/units/u3" ]'
check "protected: a leased slot is kept although it is the oldest" '[ -d "$DQ_CACHE_ROOT/units/pool-9" ]'
check "protected: a unit modified minutes ago is kept" '[ -d "$DQ_CACHE_ROOT/units/fresh" ]'
check "cargo: the least recently modified idle profile is removed WHOLE (never trimmed file by file)" '[ ! -e "$DQ_CACHE_ROOT/targets/lane1/analyze-test/debug" ]'
check "cargo: the other profile of the same target is intact, every file" '[ -f "$DQ_CACHE_ROOT/targets/lane1/analyze-test/release/deps/d1.rlib" ] && [ -d "$DQ_CACHE_ROOT/targets/lane1/analyze-test/release/.fingerprint/c" ]'
check "cargo: a profile in use is kept whole although its oldest file is old (no file-level eviction)" '[ "$(ls "$DQ_CACHE_ROOT/targets/lane2/t/debug/deps" | wc -l)" = 4 ] && [ -d "$DQ_CACHE_ROOT/targets/lane2/t/debug/.fingerprint" ]'
check "cargo: a worktree that holds a machine slot is never touched" '[ "$(ls "$DQ_CACHE_ROOT/targets/lane3/t/debug/deps" | wc -l)" = 3 ] && grep -q "protected (holds a machine slot): lane3" <<<"$out"'
check "cargo: a leased slot is never touched and reported protected" '[ "$(ls "$DQ_CACHE_ROOT/targets/pool-8/t/debug/deps" | wc -l)" = 3 ] && grep -q "protected (leased pool slot): pool-8" <<<"$out"'
check "cargo: a permanent worktree is never touched and reported protected" '[ "$(ls "$DQ_CACHE_ROOT/targets/perm-wt/t/debug/deps" | wc -l)" = 3 ] && grep -q "protected (permanent worktree): perm-wt" <<<"$out"'
check "cargo: an idle owner with no profile left is removed whole" '[ ! -e "$DQ_CACHE_ROOT/targets/lane4" ]'
check "cargo: a worktree own target loses an idle profile whole, keeps the fresh one with its old file" '[ ! -e "$DQ_WT_ROOT/lane-a/tools/analyze/target/debug" ] && [ -f "$DQ_WT_ROOT/lane-a/tools/analyze/target/fresh/deps/d1.rlib" ]'
check "cargo: a permanent worktree own target is never touched" '[ "$(ls "$DQ_WT_ROOT/perm-wt/tools/analyze/target/debug/deps" | wc -l)" = 3 ]'
check "cargo: no tombstone is left behind" '[ -z "$(find "$DQ_CACHE_ROOT/targets" "$DQ_WT_ROOT" -name ".evicting-*" 2>/dev/null)" ]'
check "files-lru: the oldest file goes, the newest is kept" '[ ! -f "$DQ_CACHE_ROOT/logs/f3.dat" ] && [ -f "$DQ_CACHE_ROOT/logs/f1.dat" ]'
check "unknown directory that is not clearly a cache is reported, not removed" '[ -d "$DQ_CACHE_ROOT/mystery" ] && grep -q "not clearly a cache" <<<"$out"'
check "unknown directory that is clearly a cache (dmb-*) is removed when idle" '[ ! -d "$DQ_CACHE_ROOT/dmb-probe-old" ]'
check "coordination state (train queue, lane-pool self) is never touched, even if the manifest does not name it" '[ -f "$DQ_CACHE_ROOT/train/queue/q1.q" ] && [ -f "$DQ_CACHE_ROOT/lane-pool/self/x" ]'
check "unknown directory with a CACHEDIR.TAG (a stray build target) is removed when idle" '[ ! -d "$DQ_CACHE_ROOT/stray-target" ]'
check "unknown stray file is removed when idle" '[ ! -f "$DQ_CACHE_ROOT/stray.log" ]'
check "unknown but busy directory is kept" '[ -d "$DQ_CACHE_ROOT/mystery-busy" ]'
check "state table is never evicted" '[ -f "$DQ_CACHE_ROOT/slots/owner" ]'
check "worktree growth: the file past the age cap goes" '[ ! -f "$DQ_WT_ROOT/lane-a/data/test-runs/old.log" ]'
check "worktree growth: capped to 1 MB, the file in use stays" '[ -f "$DQ_WT_ROOT/lane-a/data/test-runs/new.log" ] && [ ! -f "$DQ_WT_ROOT/lane-a/data/test-runs/mid.log" ]'
check "tracked: a committed file past the age and size caps is never deleted, and git sees no deletion" '[ -f "$DQ_WT_ROOT/lane-a/data/test-runs/tracked.log" ] && [ -z "$(git -C "$DQ_WT_ROOT/lane-a" status --porcelain | grep "^ D")" ]'
check "the report names the tables and the free space" 'grep -q "units " <<<"$out" && grep -q "free now" <<<"$out"'

# an excluded worktree is never touched
mkdir -p "$DQ_WT_ROOT/lane-x/data/test-runs"; git init -q "$DQ_WT_ROOT/lane-x"
mk "$DQ_WT_ROOT/lane-x/data/test-runs/old.log" 1048576 "10 days ago"
DQ_DISK_EXCLUDE_WT="lane-x" bash tools/dq_disk_budget.sh enforce --force >/dev/null 2>&1
check "DQ_DISK_EXCLUDE_WT: an excluded worktree is left alone" '[ -f "$DQ_WT_ROOT/lane-x/data/test-runs/old.log" ]'

# whole-cache total cap: with a total of 0 every unit not in use is squeezed out, oldest first
sed -i 's/^total_gb = 60/total_gb = 0/' "$T/m.toml"
unit "$DQ_CACHE_ROOT/small/s1" "3 days ago"; unit "$DQ_CACHE_ROOT/small/s2" "2 days ago"
bash tools/dq_disk_budget.sh enforce --force >/dev/null 2>&1
check "total cap: the cache is squeezed below its tables' own caps" '[ ! -d "$DQ_CACHE_ROOT/small/s1" ] && [ ! -d "$DQ_CACHE_ROOT/small/s2" ]'
sed -i 's/^total_gb = 0/total_gb = 60/' "$T/m.toml"

# the disk floor
DQ_DISK_FREE_GB=10 bash tools/dq_disk_budget.sh gate lease --sync --throttle 60 >"$T/gate.out" 2>&1; rc=$?
check "floor: gate refuses (exit 4) below the floor with a clear message" '[ "$rc" = 4 ] && grep -q "REFUSED lease: only 10 GB free" "$T/gate.out"'
DQ_DISK_FREE_GB=80 bash tools/dq_disk_budget.sh gate lease --sync --throttle 60 >/dev/null 2>&1; rc=$?
check "floor: gate passes above the floor" '[ "$rc" = 0 ]'
tout="$(DQ_DISK_FREE_GB=60 DQ_DISK_TARGET_GB=80 bash tools/dq_disk_budget.sh enforce --dry-run 2>&1)"
check "target: under the free-space target the housekeeping runs aggressive (above the floor)" 'grep -q "under the target of 80 GB: aggressive" <<<"$tout" && grep -q "scale 50%" <<<"$tout"'
tout="$(DQ_DISK_FREE_GB=90 DQ_DISK_TARGET_GB=80 bash tools/dq_disk_budget.sh enforce --dry-run 2>&1)"
check "target: above it the housekeeping stays normal" '! grep -q "under the target" <<<"$tout" && grep -q "scale 100%" <<<"$tout"'
DQ_DISK_FREE_GB=10 DQ_DISK_FLOOR_GB=5 bash tools/dq_disk_budget.sh gate lease --sync --throttle 60 >/dev/null 2>&1; rc=$?
check "floor: DQ_DISK_FLOOR_GB lowers it" '[ "$rc" = 0 ]'

# a profile whose .cargo-lock a running cargo holds is refused via flock, where the platform has it (Windows refuses the rename of an open one)
if command -v flock >/dev/null 2>&1; then
	cprofile "$DQ_CACHE_ROOT/targets/lane5/t/debug" "6 days ago" 3; : >"$DQ_CACHE_ROOT/targets/lane5/t/debug/.cargo-lock"; touch -d "6 days ago" "$DQ_CACHE_ROOT/targets/lane5/t/debug"
	( flock -n 9 && sleep 6 ) 9>"$DQ_CACHE_ROOT/targets/lane5/t/debug/.cargo-lock" & holder=$!
	sleep 1; bash tools/dq_disk_budget.sh enforce --force >/dev/null 2>&1; wait "$holder"
	check "cargo: a profile whose .cargo-lock a running cargo holds is never touched" '[ "$(ls "$DQ_CACHE_ROOT/targets/lane5/t/debug/deps" | wc -l)" = 3 ]'
fi

# the gate fails ONLY on a real floor breach: every other failure is a warning and exit 0
mkdir "$DQ_CACHE_ROOT/disk-budget/enforce.lock" 2>/dev/null || { mkdir -p "$DQ_CACHE_ROOT/disk-budget"; mkdir "$DQ_CACHE_ROOT/disk-budget/enforce.lock"; }
rm -f "$DQ_CACHE_ROOT/disk-budget/enforce.stamp"
DQ_DISK_FREE_GB=80 bash tools/dq_disk_budget.sh gate lease --sync --throttle 60 >/dev/null 2>&1; rc=$?
check "gate: a busy enforce lock above the floor is not a refusal" '[ "$rc" = 0 ]'
DQ_DISK_FREE_GB=10 bash tools/dq_disk_budget.sh gate lease --sync >"$T/gate2.out" 2>&1; rc=$?
check "gate: below the floor with enforce unable to run it still refuses, naming the free GB and the floor" '[ "$rc" = 4 ] && grep -q "REFUSED lease: only 10 GB free .*floor 50 GB" "$T/gate2.out"'
rmdir "$DQ_CACHE_ROOT/disk-budget/enforce.lock"
DQ_DISK_MANIFEST="$T/nonexistent.toml" DQ_DISK_FREE_GB=80 bash tools/dq_disk_budget.sh gate lease --sync >"$T/gate3.out" 2>&1; rc=$?
check "gate: a missing manifest is a warning, exit 0, no REFUSED" '[ "$rc" = 0 ] && ! grep -q REFUSED "$T/gate3.out" && grep -q WARNING "$T/gate3.out"'
env -u DQ_DISK_FREE_GB DQ_CACHE_ROOT="$T/no/such/cache" DQ_DISK_STATE="$T/gstate" bash tools/dq_disk_budget.sh gate lease --sync >"$T/gate4.out" 2>&1; rc=$?
check "gate: free space that cannot be read is a warning, exit 0, no REFUSED" '[ "$rc" = 0 ] && ! grep -q REFUSED "$T/gate4.out" && grep -q "cannot read the free space" "$T/gate4.out"'
check "train: only the gate's exit 4 skips a cycle" 'grep -q "drc\" -eq 4" tools/dq_train.sh && grep -q "^SNAP_FILES=(.*dq_disk_budget.sh ci/disk_budget.toml" tools/dq_train.sh'

# a table over its cap because its units are protected says so, with the protected size
cat >>"$T/m.toml" <<'TOML'
[cache.held]
policy = children-lru
cap_mb = 1
protect = leased-slot
TOML
unit "$DQ_CACHE_ROOT/held/pool-h1" "5 days ago"; unit "$DQ_CACHE_ROOT/held/pool-h2" "6 days ago"
: >"$DQ_CACHE_ROOT/lane-pool/pool-h1.lease"; : >"$DQ_CACHE_ROOT/lane-pool/pool-h2.lease"
out="$(bash tools/dq_disk_budget.sh enforce --force 2>&1)"
check "over cap: a table held over its cap by leased slots is reported with the protected size" 'grep -q "OVER CAP held: 2 MB against 1 MB; protected .*: 2 MB in 2 unit" <<<"$out" && [ -d "$DQ_CACHE_ROOT/held/pool-h1" ]'
# status measures fresh: a stale index must not show an old size
mk "$DQ_CACHE_ROOT/units/grow.dat" 5242880 "1 minute ago"
st="$(bash tools/dq_disk_budget.sh status 2>&1)"
check "status: sizes are measured now, not read from the index" 'grep -Eq "^  units +([5-9]|[1-9][0-9]) MB" <<<"$st"'
# the real manifest parses
DQ_DISK_MANIFEST="$PWD/tools/ci/disk_budget.toml" DQ_CACHE_ROOT="$T/empty" bash tools/dq_disk_budget.sh status >/dev/null 2>&1; rc=$?
check "the real manifest parses" '[ "$rc" = 0 ]'
if [ "$fail" = 0 ]; then echo "test_disk_budget: ok"; else echo "test_disk_budget: FAILED"; fi
exit "$fail"
