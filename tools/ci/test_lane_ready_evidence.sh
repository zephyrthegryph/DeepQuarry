#!/usr/bin/env bash
export DQ_LEGACY_LAND=1 # the retired per-lane scripts are still tested until they are deleted
# Exercise the real lane-ready wrapper with controlled gate outputs, no build.
set -euo pipefail
source_root="$(git rev-parse --show-toplevel)"
scratch="$(mktemp -d E:/projects/dq-wt/lane-ready-evidence.XXXXXX)"
echo "lane-ready evidence fixture: $scratch"
mkdir -p "$scratch/tools"
cp "${DQ_EVIDENCE_WRAPPER:-$source_root/tools/dq_lane_ready.sh}" "$scratch/tools/dq_lane_ready.sh"
for helper in dq_git_safe dq_run_lock dq_proof_cache dq_declared_tests; do cp "$source_root/tools/$helper.sh" "$scratch/tools/$helper.sh"; done
cd "$scratch"
git init -q -b codex/evidence
git config user.name 'Lane evidence test'
git config user.email 'lane-evidence@example.invalid'
printf '/data/\n' >.gitignore
# The merge stub stands for a master merge that brings in the fixed wrapper (DQ_REAL_WRAPPER) over a stale running copy.
cat >tools/dq_merge_master.sh <<'MERGE'
#!/usr/bin/env bash
if [ -n "${DQ_REAL_WRAPPER:-}" ]; then
  cp "$DQ_REAL_WRAPPER" tools/dq_lane_ready.sh; git add tools/dq_lane_ready.sh; git diff --cached --quiet || git commit -q -m 'Merge master (fixed wrapper)'
fi
exit 0
MERGE
printf '#!/usr/bin/env bash\nexit 0\n' >tools/dq_focused_test.sh
cat >tools/dq_merge_gates.sh <<'FIXTURE'
#!/usr/bin/env bash
set -euo pipefail
pre="$(git rev-parse HEAD)"
if [ "$DQ_EVIDENCE_FIXTURE" = shrunk ] || [ "$DQ_EVIDENCE_FIXTURE" = stale ]; then
  # The gates' baseline shrink: tests ran on the pre-shrink commit, then only a tools/ci baseline changed.
  mkdir -p tools/ci; echo shrunk >tools/ci/x_baseline.txt; git add tools/ci/x_baseline.txt; git commit -q --amend --no-edit
fi
if [ "$DQ_EVIDENCE_FIXTURE" = shrunkcode ]; then
  echo probe >>moved.txt; echo shrunk >tools/ci/x_baseline.txt; git add moved.txt tools/ci/x_baseline.txt; git commit -q --amend --no-edit
fi
if [ "$DQ_EVIDENCE_FIXTURE" = moved ]; then
  # The real gates amend the merge commit (baseline shrink, look keys): HEAD moves before the proof is named.
  echo probe >>moved.txt; git add moved.txt; git commit -q --amend --no-edit
fi
sha="$(git rev-parse HEAD)"
dir=data/merge-gates
mkdir -p "$dir"
case "$DQ_EVIDENCE_FIXTURE" in
  missing) exit 0 ;;
  incomplete|badcounts|wrongsha|wrongcommit|valid|moved|shrunk|shrunkcode|stale) ;;
  *) exit 2 ;;
esac
proof_sha="$sha"
[ "$DQ_EVIDENCE_FIXTURE" != wrongsha ] || proof_sha=0000000000000000000000000000000000000000
printf 'sha=%s\ntests=/datum/unit_test/evidence_probe\ntests_json=data/result.json\npassed=1\nfailed=0\nnew_failed=0\n' "$proof_sha" >"$dir/${sha:0:12}.ok"
printf '{"commit":"%s","counts":{"passed":1,"failed":0}}\n' "$sha" >data/result.json
case "$DQ_EVIDENCE_FIXTURE" in shrunk|shrunkcode|stale) printf '{"commit":"%s","counts":{"passed":1,"failed":0}}
' "${pre:0:10}" >data/result.json ;; esac
if [ "$DQ_EVIDENCE_FIXTURE" = wrongcommit ]; then printf '{"commit":"other","counts":{"passed":1,"failed":0}}\n' >data/result.json; fi
if [ "$DQ_EVIDENCE_FIXTURE" = incomplete ]; then exit 0; fi
for marker in dm ratchets analyze; do printf '%s\n' "$sha" >"$dir/${sha:0:12}.$marker.ok"; done
if [ "$DQ_EVIDENCE_FIXTURE" = badcounts ]; then printf '{"commit":"%s","counts":{"passed":0,"failed":0}}\n' "$sha" >data/result.json; fi
FIXTURE
git add .gitignore tools
git commit -qm 'Evidence fixture'
git update-ref refs/remotes/origin/master HEAD
for mode in missing incomplete badcounts wrongsha wrongcommit; do
  if DQ_LANE_NOTES_PUSH=0 DQ_EVIDENCE_FIXTURE="$mode" bash tools/dq_lane_ready.sh --tests /datum/unit_test/evidence_probe >"data-$mode.log" 2>&1; then
    echo "FAIL: $mode evidence was stamped" >&2
    exit 1
  fi
  if git notes --ref=lane-ready show HEAD >/dev/null 2>&1; then
    echo "FAIL: $mode left a note" >&2
    exit 1
  fi
  echo "PASS: $mode evidence refused"
done
# Test logs are intentionally untracked non-sources; lane-ready accepts these.
DQ_LANE_NOTES_PUSH=0 DQ_EVIDENCE_FIXTURE=valid bash tools/dq_lane_ready.sh --tests /datum/unit_test/evidence_probe >data-valid.log 2>&1
git notes --ref=lane-ready show HEAD >data/stamp.json
node -e 'const s=require("./data/stamp.json"); if (!s.ok || s.passed!==1 || s.tests[0]!=="/datum/unit_test/evidence_probe") process.exit(1)'
echo 'PASS: complete evidence stamped with an unchanged DM selector'

# Reuse must not run the gate again; missing would otherwise produce no proof.
git notes --ref=lane-ready remove HEAD >/dev/null
DQ_LANE_NOTES_PUSH=0 DQ_EVIDENCE_FIXTURE=missing bash tools/dq_lane_ready.sh --reuse-gates --tests /datum/unit_test/evidence_probe >data-reuse.log 2>&1
git notes --ref=lane-ready show HEAD >/dev/null
echo 'PASS: completed exact-commit evidence reused without another gate'
git notes --ref=lane-ready remove HEAD >/dev/null
if DQ_LANE_NOTES_PUSH=0 DQ_EVIDENCE_FIXTURE=missing bash tools/dq_lane_ready.sh --reuse-gates --tests /datum/unit_test/untested_probe >data-reuse-missing-selector.log 2>&1; then
 echo 'FAIL: reuse accepted an untested selector' >&2
 exit 1
fi
if git notes --ref=lane-ready show HEAD >/dev/null 2>&1; then exit 1; fi
echo 'PASS: reuse refuses untested selectors'

# The gates may move HEAD (amend/record look keys) before naming their proof: a passing run must still stamp.
git notes --ref=lane-ready remove HEAD >/dev/null 2>&1 || true
before="$(git rev-parse HEAD)"
DQ_LANE_NOTES_PUSH=0 DQ_EVIDENCE_FIXTURE=moved bash tools/dq_lane_ready.sh --tests /datum/unit_test/evidence_probe >data-moved.log 2>&1 || { cat data-moved.log >&2; echo 'FAIL: gates that moved HEAD were not stamped' >&2; exit 1; }
[ "$(git rev-parse HEAD)" != "$before" ] || { echo 'FAIL: fixture did not move HEAD' >&2; exit 1; }
git notes --ref=lane-ready show HEAD >/dev/null
echo 'PASS: gates that moved HEAD still stamp'
# The refusal names expected and found.
grep -q 'expected:' data-wrongsha.log && grep -q 'found:' data-wrongsha.log || { echo 'FAIL: refusal lacks expected/found' >&2; exit 1; }
echo 'PASS: refusal prints expected vs found'

# The exact reported sequence: the gates shrink baselines after the run, so the evidence names the pre-shrink commit.
git notes --ref=lane-ready remove HEAD >/dev/null 2>&1 || true
DQ_LANE_NOTES_PUSH=0 DQ_EVIDENCE_FIXTURE=shrunk bash tools/dq_lane_ready.sh --tests /datum/unit_test/evidence_probe >data-shrunk.log 2>&1 || { cat data-shrunk.log >&2; echo 'FAIL: baseline-shrunk HEAD was not stamped' >&2; exit 1; }
git notes --ref=lane-ready show HEAD >/dev/null
grep -q 'only tools/ci/\*_baseline.txt ' data-shrunk.log || { echo 'FAIL: no matched-commits line' >&2; exit 1; }
echo 'PASS: evidence for the pre-shrink commit is accepted when only baselines differ'
git notes --ref=lane-ready remove HEAD >/dev/null 2>&1 || true
if DQ_LANE_NOTES_PUSH=0 DQ_EVIDENCE_FIXTURE=shrunkcode bash tools/dq_lane_ready.sh --tests /datum/unit_test/evidence_probe >data-shrunkcode.log 2>&1; then
 echo 'FAIL: evidence accepted across a non-baseline change' >&2
 exit 1
fi
echo 'PASS: a non-baseline difference gets no evidence alias'

# The real sequence: the running wrapper predates the fix; the master merge brings the fixed one, then the gates (which ran their tests on the
# merge commit) amend it with a baseline shrink. The stale copy cannot match the evidence, so the wrapper must re-run the merged copy.
git notes --ref=lane-ready remove HEAD >/dev/null 2>&1 || true
cp tools/dq_lane_ready.sh real_wrapper.sh
sed 's/^\(\s*\)evidence_alt="\$tested"/:/' real_wrapper.sh >tools/dq_lane_ready.sh
if cmp -s real_wrapper.sh tools/dq_lane_ready.sh; then echo 'FAIL: could not make the stale wrapper' >&2; exit 1; fi
git add tools/dq_lane_ready.sh; git commit -q -m 'stale wrapper'
DQ_REAL_WRAPPER="$PWD/real_wrapper.sh" DQ_LANE_NOTES_PUSH=0 DQ_EVIDENCE_FIXTURE=stale bash tools/dq_lane_ready.sh --tests /datum/unit_test/evidence_probe >data-stale.log 2>&1 || { cat data-stale.log >&2; echo 'FAIL: stale wrapper was not replaced by the merged copy' >&2; exit 1; }
grep -q 're-running the merged copy' data-stale.log && git notes --ref=lane-ready show HEAD >/dev/null
echo 'PASS: a wrapper the merge replaced re-runs the merged copy and stamps across the baseline shrink'
