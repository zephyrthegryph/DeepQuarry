#!/usr/bin/env bash
# Exercise the real lane-ready wrapper with controlled gate outputs, no build.
set -euo pipefail
source_root="$(git rev-parse --show-toplevel)"
scratch="$(mktemp -d E:/projects/dq-wt/lane-ready-evidence.XXXXXX)"
echo "lane-ready evidence fixture: $scratch"
mkdir -p "$scratch/tools"
cp "$source_root/tools/dq_lane_ready.sh" "$scratch/tools/"
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
  incomplete|badcounts|valid) ;;
  *) exit 2 ;;
esac
printf '%s\ntests_json=data/result.json\npassed=1\nfailed=0\nnew_failed=0\n' "$sha" >"$dir/${sha:0:12}.ok"
printf '{"counts":{"passed":1,"failed":0}}\n' >data/result.json
if [ "$DQ_EVIDENCE_FIXTURE" = incomplete ]; then exit 0; fi
for marker in dm ratchets analyze; do printf '%s\n' "$sha" >"$dir/${sha:0:12}.$marker.ok"; done
if [ "$DQ_EVIDENCE_FIXTURE" = badcounts ]; then printf '{"counts":{"passed":0,"failed":0}}\n' >data/result.json; fi
FIXTURE
git add .gitignore tools
git commit -qm 'Evidence fixture'
git update-ref refs/remotes/origin/master HEAD
for mode in missing incomplete badcounts; do
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
