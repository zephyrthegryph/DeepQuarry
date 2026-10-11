#!/usr/bin/env bash
# Exercise the real lane-ready wrapper with controlled gate outputs, no build.
set -euo pipefail
source_root="$(git rev-parse --show-toplevel)"
scratch="$(mktemp -d E:/projects/dq-wt/lane-ready-evidence.XXXXXX)"
echo "lane-ready evidence fixture: $scratch"
mkdir -p "$scratch/tools"
cp "${DQ_EVIDENCE_WRAPPER:-$source_root/tools/dq_lane_ready.sh}" "$scratch/tools/dq_lane_ready.sh"
cd "$scratch"
git init -q -b codex/evidence
git config user.name 'Lane evidence test'
git config user.email 'lane-evidence@example.invalid'
printf '/data/\n' >.gitignore
printf '#!/usr/bin/env bash\nexit 0\n' >tools/dq_merge_master.sh
cat >tools/dq_merge_gates.sh <<'FIXTURE'
#!/usr/bin/env bash
set -euo pipefail
sha="$(git rev-parse HEAD)"
dir=data/merge-gates
mkdir -p "$dir"
case "$DQ_EVIDENCE_FIXTURE" in
  missing) exit 0 ;;
  incomplete|badcounts|wrongsha|wrongcommit|valid) ;;
  *) exit 2 ;;
esac
proof_sha="$sha"
[ "$DQ_EVIDENCE_FIXTURE" != wrongsha ] || proof_sha=0000000000000000000000000000000000000000
printf 'sha=%s\ntests=/datum/unit_test/evidence_probe\ntests_json=data/result.json\npassed=1\nfailed=0\nnew_failed=0\n' "$proof_sha" >"$dir/${sha:0:12}.ok"
printf '{"commit":"%s","counts":{"passed":1,"failed":0}}\n' "$sha" >data/result.json
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
