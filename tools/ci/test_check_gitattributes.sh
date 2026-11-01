#!/usr/bin/env bash
# Tests tools/ci/check_gitattributes.sh in a scratch repository: a live path passes; a moved or deleted path, a glob that matches
# nothing and an unknown merge driver each fail with the line; bare type patterns and `*` are not judged.
set -uo pipefail
here="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok() { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1 [$2]"; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/r/tools/ci" "$tmp/r/code/tests" "$tmp/r/code/x"
cp "$here/tools/ci/check_gitattributes.sh" "$tmp/r/tools/ci/"
echo 'git config merge.dq-ok.driver' >"$tmp/r/tools/dq_git_safe.sh"
echo 'merge.dq-ok.driver=x' >>"$tmp/r/tools/dq_git_safe.sh"
echo a >"$tmp/r/code/tests/_unit_tests.dm"; echo b >"$tmp/r/code/x/one.dm"
(cd "$tmp/r" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm init) >/dev/null 2>&1
run() { # <attributes text>: prints the checker's output, sets $rc
	printf '%s\n' "$1" >"$tmp/r/.gitattributes"
	out="$(cd "$tmp/r" && bash tools/ci/check_gitattributes.sh 2>&1)"; rc=$?
}
run $'* text=auto\n*.htm text\ncode/tests/_unit_tests.dm merge=union\ncode/x/*.dm merge=dq-ok'
check "live paths, a matching glob, a known driver, bare patterns and * pass" '[ "$rc" -eq 0 ]'
run $'code/modules/unit_tests/_unit_tests.dm merge=union'
check "a moved path fails and names the line" '[ "$rc" -ne 0 ] && grep -q ".gitattributes:1: .code/modules/unit_tests/_unit_tests.dm. matches no tracked file" <<<"$out"'
run $'code/y/*.dm merge=union'
check "a glob matching nothing fails" '[ "$rc" -ne 0 ]'
run $'code/x/one.dm merge=dq-typo'
check "an unknown merge driver fails" '[ "$rc" -ne 0 ] && grep -q "merge driver .dq-typo." <<<"$out"'
# the repository's own file is clean
check "this repository's .gitattributes is clean" '(cd "$here" && bash tools/ci/check_gitattributes.sh >/dev/null)'
[ "$fail" -eq 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
