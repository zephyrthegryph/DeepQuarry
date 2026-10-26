#!/usr/bin/env bash
# Test for tools/ci/baseline_merge_driver.sh, in a scratch repo under mktemp, through real `git merge` with the driver
# supplied by tools/dq_git_safe.sh. bash tools/ci/test_baseline_merge_driver.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$2" = "$3" ]; then echo "ok: $1"; else echo "FAIL: $1"; echo "--- want"; echo "$2"; echo "--- got"; echo "$3"; fails=$((fails + 1)); fi; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
. "$ROOT/tools/dq_git_safe.sh"
cd "$T" && git init -q -b master . && mkdir -p tools/ci
cp "$ROOT/tools/ci/baseline_merge_driver.sh" tools/ci/
echo 'tools/ci/*_baseline.txt merge=dq-baseline' >.gitattributes
P=$'#hdr\nr\ta\tx\nr\tb\ty\nr\tc\tz\nr\td\tw\n'
printf '%s' "$P" >tools/ci/a_baseline.txt
printf '# ceilings\ninit_allow 85\nusr_allow 5\nusr_content 82\n' >tools/ci/c_baseline.txt
printf '#h\nr\ta\nr\tb\nr\tc\nr\td\nr\te\n' >tools/ci/n_baseline.txt
printf 'free form text\nmore\n' >tools/ci/u_baseline.txt
git add -A && git commit -qm base
git switch -q -c one; git switch -q master; git switch -q -c two master
# side one: drops a; ceilings 80 / key usr_allow removed
git switch -q one
printf '#hdr\nr\tb\ty\nr\tc\tz\nr\td\tw\n' >tools/ci/a_baseline.txt
printf '# ceilings\ninit_allow 80\nusr_content 82\n' >tools/ci/c_baseline.txt
printf 'free form text\nmore one\n' >tools/ci/u_baseline.txt
printf '#h\nr\tb\nr\tc\nr\tnew1\nr\td\nr\te\n' >tools/ci/n_baseline.txt
git commit -qam one
git switch -q two
printf '#hdr\nr\ta\tx\nr\tb\ty\nr\tc\tz\n' >tools/ci/a_baseline.txt
printf '# ceilings\ninit_allow 83\nusr_allow 4\nusr_content 70\n' >tools/ci/c_baseline.txt
printf 'free form text\nmore two\n' >tools/ci/u_baseline.txt
printf '#h\nr\ta\nr\tb\nr\tc\nr\te\nr\tnew2\n' >tools/ci/n_baseline.txt
git commit -qam two
git merge -q --no-edit one >/dev/null 2>&1
check "rows: each side drops a different row" $'#hdr\nr\tb\ty\nr\tc\tz' "$(cat tools/ci/a_baseline.txt)"
check "rows added on each side are kept in place, drops stay dropped" $'#h\nr\tb\nr\tc\nr\tnew1\nr\te\nr\tnew2' "$(cat tools/ci/n_baseline.txt)"
check "ceilings: smaller value, removed key stays removed" $'# ceilings\ninit_allow 80\nusr_content 70' "$(cat tools/ci/c_baseline.txt)"
if grep -q '<<<<<<<' tools/ci/u_baseline.txt; then echo "ok: unsupported format falls back to a conflict"; else echo "FAIL: unsupported format did not conflict"; fails=$((fails + 1)); fi
git merge --abort >/dev/null 2>&1
want="dq-baseline"; got="$(git -C "$ROOT" check-attr merge tools/ci/sys_baseline/dx_review.txt tools/ci/lint_x_baseline.txt | awk "{print \$NF}" | sort -u)"
check "sys_baseline rows and ratchet baselines both use the driver" "$want" "$got"
[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
