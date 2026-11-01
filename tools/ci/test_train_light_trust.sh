#!/usr/bin/env bash
# What makes a light lane repeat its checks (tools/train/light_trust.py): an unrelated tool on master does not, a real dependency does.
#   bash tools/ci/test_train_light_trust.sh
set -uo pipefail
for _v in $(compgen -e | grep -E '^(DQ_|GIT_CONFIG_)'); do unset "$_v"; done; unset _v
here="$(cd "$(dirname "$0")/../.." && pwd)"
py_tool="$(cygpath -m "$here/tools/train/light_trust.py" 2>/dev/null || echo "$here/tools/train/light_trust.py")" # Windows Python takes no MSYS path
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fail=0
ok() { echo "PASS: $1"; }; bad() { echo "FAIL: $1"; fail=1; }
cd "$tmp"; git init -q r; cd r; git config user.email t@t; git config user.name t
mkdir -p tools/ci tools/train tools/build doc code
cp "$here/tools/dq_light_checks.sh" "$here/tools/dq_light_paths.sh" tools/
echo 'echo rdeps' >tools/light_cargo_rdeps.py
# dq_foo runs dq_helper; test_foo runs dq_foo and reads a data file; dq_other and test_other are unrelated; a far tool names the build system
printf '#!/usr/bin/env bash\n. tools/dq_helper.sh\nbash tools/build/build.sh gen\necho "see doc/c.md"\n# tools/dq_only_in_a_comment.sh\n' >tools/dq_foo.sh
echo 'echo helper' >tools/dq_helper.sh; echo 'echo comment' >tools/dq_only_in_a_comment.sh
printf '#!/usr/bin/env bash\nbash tools/dq_foo.sh\ngrep x tools/ci/foo_data.conf\ngrep x doc/b.md\nmkdir -p code/tests\necho >code/a.dm\n' >tools/ci/test_foo.sh
echo x >tools/ci/foo_data.conf
echo 'echo other' >tools/dq_other.sh; echo 'echo other' >tools/ci/test_other.sh
echo 'echo build' >tools/build/build.sh; echo 'x' >tools/build/build.ts
echo x >code/a.dm; echo '[b](b.md)' >doc/a.md; echo b >doc/b.md; echo c >doc/c.md; echo 'x' >tools/ci/check_x.sh
git add -A; git commit -qm init; git branch -M master
base="$(git rev-parse HEAD)"
git switch -qc lane/tool; echo '# edit' >>tools/dq_foo.sh; git commit -qam tool
git switch -qc lane/doc master; echo more >>doc/a.md; git commit -qam doc
git switch -qc lane/lint master; echo '# edit' >>tools/ci/check_x.sh; git commit -qam lint
git switch -qc lane/ci master; echo '# edit' >>tools/ci/test_foo.sh; git commit -qam ci
git switch -q master

trust() { # <lane> <selftests> : after a commit on a scratch master made by change()
	python3 "$py_tool" --repo . --base "$base" --master "$(git rev-parse HEAD)" --tip "$(git rev-parse "$1")" --selftests "$2"
}
# on_master <description> <command...>: a one-commit master, undone by moving the branch back with switch -C (a scratch repository)
on_master() { git switch -qC "m$RANDOM" "$base"; eval "$1"; git add -A; git commit -qm change; }
expect_trust() { # <name> <lane> <selftests> <change>
	on_master "$4"; out="$(trust "$2" "$3")"; rc=$?
	if [ "$rc" -eq 0 ]; then ok "$1"; else bad "$1 (rc=$rc: $out)"; fi
}
expect_repeat() { # <name> <lane> <selftests> <change> <word the reason names>
	on_master "$4"; out="$(trust "$2" "$3")"; rc=$?
	if [ "$rc" -eq 1 ] && grep -qF "$5" <<<"$out"; then ok "$1"; else bad "$1 (rc=$rc: $out)"; fi
}

# narrower than a directory: 1 November 03:13Z, 473 s for a neighbour in tools/ci
expect_trust "a self-test beside the lane's in tools/ci does not repeat the checks" lane/ci test_foo.sh 'echo y >>tools/ci/test_other.sh'
expect_trust "an unrelated tool does not" lane/tool test_foo.sh 'echo y >>tools/dq_other.sh'
expect_trust "game code does not (the checks read none of it, a fixture's name is not a read)" lane/tool test_foo.sh 'echo y >>code/a.dm'
expect_trust "what only a comment names does not" lane/tool test_foo.sh 'echo y >>tools/dq_only_in_a_comment.sh'
expect_trust "a file behind the barrier, reached only through a named build script, does not" lane/tool test_foo.sh 'echo y >>tools/build/build.ts'
expect_trust "a doc a tool only prints in a message does not" lane/tool test_foo.sh 'echo y >>doc/c.md'
expect_trust "a doc lane: another doc that its links do not name" lane/doc "" 'echo y >>doc/c.md'
# the real dependencies, all of which the old directory rule missed or found by luck
expect_repeat "the lane's own file does" lane/tool test_foo.sh 'echo y >>tools/dq_foo.sh' dq_foo.sh
expect_repeat "a tool the lane's tool sources does" lane/tool test_foo.sh 'echo y >>tools/dq_helper.sh' dq_helper.sh
expect_repeat "the lane's self-test does" lane/tool test_foo.sh 'echo y >>tools/ci/test_foo.sh' test_foo.sh
expect_repeat "a data file the self-test reads does" lane/tool test_foo.sh 'echo y >>tools/ci/foo_data.conf' foo_data.conf
expect_repeat "the build script the lane's tool names does" lane/tool test_foo.sh 'echo y >>tools/build/build.sh' build.sh
expect_repeat "a doc the self-test itself names does" lane/tool test_foo.sh 'echo y >>doc/b.md' doc/b.md
expect_repeat "the checks themselves do" lane/doc "" 'echo y >>tools/dq_light_checks.sh' dq_light_checks.sh
expect_repeat "a lint input reads the whole tree: game code does" lane/lint "" 'echo y >>code/a.dm' code/a.dm
expect_repeat "a doc's link target deleted on master does" lane/doc "" 'rm doc/b.md' b.md

# TGUI: its checks read tgui/, and tsc reads types generated from code/ by the analyzer through the build
git switch -qC tguibase "$base"; mkdir -p tgui/x tools/analyze; echo a >tgui/x/a.ts; echo a >tgui/x/b.ts; echo a >tgui/x/r.md; echo a >tools/analyze/g.rs; git add -A; git commit -qm tgui; tb="$(git rev-parse HEAD)"
git switch -qc lane/tgui; echo y >>tgui/x/a.ts; git commit -qam t
tgt() { git switch -qC "m$RANDOM" "$tb"; echo y >>"$1"; git add -A; git commit -qm m; python3 "$py_tool" --repo . --base "$tb" --master HEAD --tip lane/tgui; }
for f in tgui/x/b.ts code/a.dm tools/analyze/g.rs tools/build/build.ts; do out="$(tgt "$f")"; rc=$?; if [ "$rc" = 1 ]; then ok "a TGUI lane repeats its checks for $f"; else bad "TGUI lane, $f: rc=$rc $out"; fi; done
for f in tools/dq_other.sh tgui/x/r.md; do out="$(tgt "$f")"; rc=$?; if [ "$rc" = 0 ]; then ok "a TGUI lane does not for $f"; else bad "TGUI lane, $f: rc=$rc $out"; fi; done

# a failure to tell is not a pass
on_master 'echo y >>tools/dq_other.sh'
python3 "$py_tool" --repo . --base nosuchref --master HEAD --tip lane/tool >/dev/null 2>&1; rc=$?
if [ "$rc" -ne 0 ]; then ok "an unknown commit fails closed (rc=$rc)"; else bad "an unknown commit passed"; fi

# the self-test map has one source: the checks' map, read through --selftests-for
out="$(printf 'tools/ci/test_foo.sh\r\ntools/dq_other.sh\ndoc/a.md\n' | bash tools/dq_light_checks.sh --selftests-for)"
case " $out " in *" test_foo.sh "*) ok "--selftests-for maps a changed self-test (CRLF input too)" ;; *) bad "--selftests-for: $out" ;; esac
case " $out " in *" test_other.sh "*) ok "--selftests-for maps a tool to its self-test" ;; *) bad "--selftests-for: $out" ;; esac

# Rust: a dependency of the lane's crate does, an independent crate does not
if command -v cargo >/dev/null 2>&1; then
	git switch -qC rust "$base"
	mkdir -p tools/w/a/src tools/w/b/src tools/w/c/src
	printf '[workspace]\nmembers=["a","b","c"]\nresolver="2"\n' >tools/w/Cargo.toml
	printf '[package]\nname="a"\nversion="0.1.0"\nedition="2021"\n[dependencies]\nb={path="../b"}\n' >tools/w/a/Cargo.toml
	printf '[package]\nname="b"\nversion="0.1.0"\nedition="2021"\n' >tools/w/b/Cargo.toml
	printf '[package]\nname="c"\nversion="0.1.0"\nedition="2021"\n' >tools/w/c/Cargo.toml
	for c in a b c; do echo >tools/w/$c/src/lib.rs; done
	git add -A; git commit -qm crates; rbase="$(git rev-parse HEAD)"
	git switch -qc lane/rust; echo '// edit' >>tools/w/a/src/lib.rs; git commit -qam rust
	rtrust() { git switch -qC "m$RANDOM" "$rbase"; echo '// y' >>"$1"; git add -A; git commit -qm m; python3 "$py_tool" --repo . --base "$rbase" --master HEAD --tip lane/rust; }
	out="$(rtrust tools/w/b/src/lib.rs)"; rc=$?
	if [ "$rc" -eq 1 ]; then ok "a path dependency of the lane's crate repeats its cargo tests (the old rule called two crates disjoint)"; else bad "dependency crate: rc=$rc $out"; fi
	out="$(rtrust tools/w/c/src/lib.rs)"; rc=$?
	if [ "$rc" -eq 0 ]; then ok "an independent crate of the workspace does not"; else bad "independent crate: rc=$rc $out"; fi
fi
grep -q 'light_trust.py' "$here/tools/dq_train.sh" && ok "dq_train.sh's light_trust asks this tool" || bad "dq_train.sh does not call light_trust.py"
! grep -q 'light_area' "$here/tools/dq_train.sh" && ok "the directory rule is gone" || bad "light_area is still in dq_train.sh"
[ "$fail" -eq 0 ] && echo "ALL PASSED" || { echo "SOME FAILED"; exit 1; }
