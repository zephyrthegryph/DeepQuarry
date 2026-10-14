"""Prepare attributes only for closed, explicitly owned Windows output inodes.

Callers authenticate successful output receipts before supplying marked bulky roots.
This module never removes files and fails closed on unsupported native metadata.
"""
import ctypes
import json
import os
from pathlib import Path
import re
import stat
import subprocess

MARKER = ".dmb-benchmark-owned.json"
READONLY = 1
REPARSE = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)


def _safe_path(value):
    path = Path(value).absolute()
    if path.drive.lower() != "e:" or path == Path("E:/"):
        raise ValueError("closed-link cleanup requires a contained E: path")
    for component in (path, *path.parents):
        info = component.lstat()
        if component.is_symlink() or getattr(info, "st_file_attributes", 0) & REPARSE:
            raise ValueError("reparse-point path or ancestor: " + str(component))
    return path.resolve(strict=True)


def _intersects(path, protected):
    return any(path == pin or path in pin.parents or pin in path.parents for pin in protected)


def _root(value, protected):
    path = _safe_path(value)
    if not path.is_dir() or _intersects(path, protected):
        raise ValueError("invalid/protected disposable root: " + str(path))
    marker_path = _safe_path(path / MARKER)
    marker = json.loads(marker_path.read_text(encoding="utf-8"))
    if marker != {"schema": 1, "owner": str(path.parent), "path": str(path)}:
        raise ValueError("disposable root marker mismatch: " + str(path))
    return path


def _native(*args):
    result = subprocess.run(["fsutil", *map(str, args)], capture_output=True,
                            text=True, errors="strict", timeout=10, check=True)
    return result.stdout


def _file_id(path):
    ids = re.findall(r"0x[0-9a-fA-F]+", _native("file", "queryfileid", path))
    if len(ids) != 1:
        raise ValueError("unrecognized native file-ID response")
    return ids[0].lower()


def _links(path):
    lines = [line.strip() for line in _native("hardlink", "list", path).splitlines()
             if line.strip()]
    if not lines or any(not line.startswith("\\") or line.startswith("\\\\") for line in lines):
        raise ValueError("unrecognized native hardlink response")
    links = tuple(sorted((_safe_path(path.drive + line) for line in lines), key=str))
    if len(set(links)) != len(links):
        raise ValueError("duplicate native hardlink response")
    return links


def _prove(path, roots, protected):
    path = _safe_path(path)
    links = _links(path)
    identity = _file_id(path)
    initial = path.stat()
    if path not in links or initial.st_nlink != len(links):
        raise ValueError("native hardlink roster/cardinality mismatch")
    for link in links:
        if not any(link.is_relative_to(root) for root in roots) or _intersects(link, protected):
            raise ValueError("inode has an external/protected link: " + str(link))
        info = link.stat()
        if (not stat.S_ISREG(info.st_mode) or info.st_nlink != len(links)
                or (info.st_dev, info.st_ino) != (initial.st_dev, initial.st_ino)
                or _file_id(link) != identity or _links(link) != links):
            raise ValueError("inode/link identity changed during proof")
    return identity, links, initial.st_dev, initial.st_ino, initial.st_size


def _clear_readonly(path):
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    get_attributes = kernel.GetFileAttributesW
    get_attributes.argtypes = [ctypes.c_wchar_p]
    get_attributes.restype = ctypes.c_uint32
    set_attributes = kernel.SetFileAttributesW
    set_attributes.argtypes = [ctypes.c_wchar_p, ctypes.c_uint32]
    set_attributes.restype = ctypes.c_int
    attributes = get_attributes(str(path))
    if attributes == 0xFFFFFFFF:
        raise ctypes.WinError(ctypes.get_last_error())
    if attributes & REPARSE:
        raise ValueError("reparse point appeared before attribute update")
    # Preserve every attribute other than READONLY; no chmod of shared paths.
    if not set_attributes(str(path), attributes & ~READONLY):
        raise ctypes.WinError(ctypes.get_last_error())


def prepare_owned_readonly(roots, protected):
    """Return prepared/blocked groups; never delete or change outsiders.

    All roots must be immediate marked children of their authenticated run owner.
    On unsupported platforms no attributes change. Any uncertain inode is blocked.
    The caller remains responsible for receipt authentication and directory removal.
    """
    report = {"status": "prepared", "prepared": [], "blocked": []}
    if os.name != "nt":
        report["status"] = "not_applicable"
        return report
    protected = tuple(Path(pin).absolute().resolve() for pin in protected)
    roots = tuple(_root(root, protected) for root in roots)
    candidates = []
    # Finish validating the whole root roster before changing any attributes.
    for root in roots:
        for directory, folders, files in os.walk(root, followlinks=False):
            for name in folders + files:
                path = _safe_path(Path(directory) / name)
                if not path.is_relative_to(root) or _intersects(path, protected):
                    raise ValueError("disposable descendant escaped/protected")
            for name in files:
                path = Path(directory) / name
                if getattr(path.stat(), "st_file_attributes", 0) & READONLY:
                    candidates.append(path)
    seen = set()
    for path in candidates:
        info = path.stat()
        key = (info.st_dev, info.st_ino)
        if key in seen:
            continue
        seen.add(key)
        try:
            proof = _prove(path, roots, protected)
            # Reauthenticate roots and re-enumerate every link immediately before
            # mutation. Completed benchmark outputs have no concurrent writers;
            # this does not offer an adversarial filesystem transaction guarantee.
            for root in roots:
                _root(root, protected)
            if _prove(path, roots, protected) != proof:
                raise ValueError("closed inode proof changed before mutation")
            _clear_readonly(path)
            report["prepared"].append({"file_id": proof[0],
                "paths": [str(link) for link in proof[1]], "physical_bytes": proof[4]})
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            report["blocked"].append({"path": str(path), "reason": str(error)})
    if report["blocked"]:
        report["status"] = "partially_prepared"
    return report

