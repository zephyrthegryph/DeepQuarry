"""Safety for every codemod: imported first by each script (`import _guard`).

  * --help / -h prints the script's docstring and exits before anything runs.
  * Dry run is the default: file writes are swallowed and counted; pass --apply to write.
  * --files a b ... / --dirs d ... restrict which files may be written, whatever the script itself read or walked.
"""
import builtins
import io
import os
import pathlib
import sys

APPLY = "--apply" in sys.argv
_SKIPPED = []
_WRITTEN = []


def _values(flag):
    if flag not in sys.argv:
        return None
    out = []
    for a in sys.argv[sys.argv.index(flag) + 1 :]:
        if a.startswith("--"):
            break
        out.append(a)
    return out


def _norm(path):
    return os.path.relpath(os.path.abspath(str(path))).replace("\\", "/")


_FILES = _values("--files")
_DIRS = _values("--dirs")
_FILES_N = {_norm(p) for p in _FILES} if _FILES is not None else None
_DIRS_N = [_norm(d).rstrip("/") + "/" for d in _DIRS] if _DIRS is not None else None


def _in_scope(path):
    n = _norm(path)
    if _FILES_N is None and _DIRS_N is None:
        return True
    if _FILES_N is not None and n in _FILES_N:
        return True
    return _DIRS_N is not None and any(n.startswith(d) for d in _DIRS_N)


def _writes(path, mode):
    return isinstance(path, (str, bytes, os.PathLike)) and any(c in mode for c in "wax+")


def _allowed(path):
    if not APPLY:
        _SKIPPED.append(_norm(path))
        return False
    if not _in_scope(path):
        _SKIPPED.append(_norm(path))
        return False
    _WRITTEN.append(_norm(path))
    return True


_real_open = builtins.open


def _open(file, mode="r", *a, **kw):
    if _writes(file, mode) and not _allowed(file):
        return io.BytesIO() if "b" in mode else io.StringIO()
    return _real_open(file, mode, *a, **kw)


def _write_text(self, data, *a, **kw):
    if not _allowed(self):
        return len(data)
    return _orig_write_text(self, data, *a, **kw)


def _write_bytes(self, data):
    if not _allowed(self):
        return len(data)
    return _orig_write_bytes(self, data)


_orig_write_text = pathlib.Path.write_text
_orig_write_bytes = pathlib.Path.write_bytes

if "--help" in sys.argv or "-h" in sys.argv:
    main_mod = sys.modules.get("__main__")
    print((getattr(main_mod, "__doc__", None) or "codemod").strip())
    print("\n  (dry run by default: --apply writes; --files / --dirs restrict what is written)")
    sys.exit(0)

builtins.open = _open
io.open = _open
pathlib.Path.write_text = _write_text
pathlib.Path.write_bytes = _write_bytes


def _report():
    if APPLY:
        if _SKIPPED:
            print("guard: %d write(s) outside --files/--dirs skipped" % len(set(_SKIPPED)), file=sys.stderr)
    else:
        n = len(set(_SKIPPED))
        print("guard: dry run, %d file(s) would be written; pass --apply to write" % n, file=sys.stderr)


import atexit

atexit.register(_report)
