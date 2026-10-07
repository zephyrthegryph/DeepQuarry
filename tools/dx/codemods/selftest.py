#!/usr/bin/env python3
"""Self-test of the text codemods (ui_declare.py, interact_declare.py): every fixtures/<codemod>/<case>.in.dm converts to <case>.out.dm, a second
run changes nothing, and a CRLF copy converts to the CRLF of the same output.   python tools/dx/codemods/selftest.py"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
CODEMODS = ["ui_declare", "interact_declare", "periodic_while", "verb_decl", "appearance_draw", "timed_task"]


def run(cwd, name, script):
    return subprocess.run([sys.executable, script, "--apply", "--files", name], cwd=cwd, capture_output=True, text=True).stdout


def read(path):
    with open(path, encoding="utf-8", newline="") as fh:
        return fh.read()


def main():
    failed = 0
    total = 0
    for codemod in CODEMODS:
        fix = os.path.join(HERE, "fixtures", codemod)
        script = os.path.join(HERE, codemod + ".py")
        cases = sorted(n[: -len(".in.dm")] for n in os.listdir(fix) if n.endswith(".in.dm"))
        for case in cases:
            total += 1
            want = read(os.path.join(fix, case + ".out.dm")).replace("\r\n", "\n")
            for crlf in (False, True):
                tag = "%s/%s%s" % (codemod, case, " (CRLF)" if crlf else "")
                with tempfile.TemporaryDirectory() as d:
                    src = read(os.path.join(fix, case + ".in.dm")).replace("\r\n", "\n")
                    if crlf:
                        src = src.replace("\n", "\r\n")
                    path = os.path.join(d, case + ".dm")
                    with open(path, "w", encoding="utf-8", newline="") as fh:
                        fh.write(src)
                    run(d, case + ".dm", script)
                    got = read(path)
                    if got != (want.replace("\n", "\r\n") if crlf else want):
                        print("FAIL %s: output differs from %s.out.dm" % (tag, case))
                        failed += 1
                        continue
                    run(d, case + ".dm", script)
                    if read(path) != got:
                        print("FAIL %s: a second run changed the output" % tag)
                        failed += 1
    print("selftest: %d cases, %d failed" % (total, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
