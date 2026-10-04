#!/usr/bin/env python3
"""Self-test of ui_declare.py: every fixtures/ui_declare/<case>.in.dm converts to <case>.out.dm, a second run changes nothing, and a CRLF copy
converts to the CRLF of the same output.   python tools/dx/codemods/selftest_ui_declare.py"""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(HERE, "fixtures", "ui_declare")
SCRIPT = os.path.join(HERE, "ui_declare.py")


def run(cwd, name):
    r = subprocess.run([sys.executable, SCRIPT, "--files", name], cwd=cwd, capture_output=True, text=True)
    return r.stdout


def read(path):
    with open(path, encoding="utf-8", newline="") as fh:
        return fh.read()


def main():
    cases = sorted(n[: -len(".in.dm")] for n in os.listdir(FIX) if n.endswith(".in.dm"))
    failed = 0
    for case in cases:
        want = read(os.path.join(FIX, case + ".out.dm")).replace("\r\n", "\n")
        for crlf in (False, True):
            with tempfile.TemporaryDirectory() as d:
                src = read(os.path.join(FIX, case + ".in.dm")).replace("\r\n", "\n")
                if crlf:
                    src = src.replace("\n", "\r\n")
                path = os.path.join(d, case + ".dm")
                with open(path, "w", encoding="utf-8", newline="") as fh:
                    fh.write(src)
                run(d, case + ".dm")
                got = read(path)
                expect = want.replace("\n", "\r\n") if crlf else want
                if got != expect:
                    print("FAIL %s%s: output differs from %s.out.dm" % (case, " (CRLF)" if crlf else "", case))
                    failed += 1
                    continue
                run(d, case + ".dm")
                if read(path) != got:
                    print("FAIL %s%s: a second run changed the output" % (case, " (CRLF)" if crlf else ""))
                    failed += 1
    print("selftest_ui_declare: %d cases, %d failed" % (len(cases), failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
