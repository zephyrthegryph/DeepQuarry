#!/usr/bin/env python3
"""Build-time step: regenerate stale .dmi files into a build-output tree.

For each foo.dmi.toml + foo.png pair under one of the source roots, emit
the corresponding .dmi into the build-output tree at the same relative
path. Example:

    icons/effects/effects.dmi.toml + icons/effects/effects.png
    -> icons/gen/icons/effects/effects.dmi

The build-output tree is wired into deepquarry.dme as a FILE_DIR that
takes precedence over the committed upstream tree — when an output .dmi
exists it shadows the committed icons/... .dmi at runtime, falling back
to upstream when missing.

Dirty rule:
    Cache a BLAKE2b digest of (PNG_bytes + separator + TOML_bytes) in a
    sidecar foo.dmi.hash next to the output .dmi. The pair is dirty when
    any of:
      * output .dmi missing
      * hash sidecar missing
      * recomputed input hash differs from sidecar

Why content-hash and not mtime: `git checkout` rewrites source-file mtimes
even when content is unchanged, so an mtime-based check considered every
file dirty after every branch switch — 2400+ files repacked for ~6 min of
work that produced byte-identical output. The hash sidecar isolates the
"did the bytes actually change" question from the "did the filesystem
update timestamps" question.

Repack itself is CPU-bound on PIL/Pillow; the dirty pass parallelises
across a thread pool (I/O bound) and the actual repack across a process
pool (true CPU work).

Usage:
    python -m tools.dq_icons.build_step --output icons/gen \
        icons modular_chomp/icons modular_dq/icons maps
"""
from __future__ import annotations

import argparse
import hashlib
import os
import sys
import time
from concurrent.futures import ProcessPoolExecutor, ThreadPoolExecutor, as_completed
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from . import repack as repack_mod  # noqa: E402

# BLAKE2b truncated to 16 bytes -> 32-char hex digest. Plenty of bits
# against accidental collision for ~10k sources; cheaper to compute and
# write than a full 64-byte digest.
_HASH_BYTES = 16
_INPUT_SEPARATOR = b"\x00png-toml-separator\x00"


def _output_dmi_path(toml: Path, output_root: Path) -> Path:
    # foo/bar/baz.dmi.toml under cwd -> output_root/foo/bar/baz.dmi
    rel = toml.with_suffix("")  # strip .toml -> foo/bar/baz.dmi
    return output_root / rel


def _hash_sidecar_path(out_dmi: Path) -> Path:
    # foo.dmi -> foo.dmi.hash
    return out_dmi.with_name(out_dmi.name + ".hash")


def _hash_inputs(png: Path, toml: Path) -> str:
    h = hashlib.blake2b(digest_size=_HASH_BYTES)
    h.update(png.read_bytes())
    h.update(_INPUT_SEPARATOR)
    h.update(toml.read_bytes())
    return h.hexdigest()


def _check_one(
    args: tuple[Path, Path],
) -> tuple[Path, Path, bool, str | None]:
    """Worker for the dirty-check thread pool.

    Returns (toml, out_dmi, dirty, current_hash). current_hash is None
    when the input is malformed (missing PNG sibling) — caller skips
    those silently the same way mtime mode used to.
    """
    toml, out_dmi = args
    png = toml.with_suffix("").with_suffix(".png")  # foo.dmi.toml -> foo.png
    if not png.exists():
        return toml, out_dmi, False, None
    current_hash = _hash_inputs(png, toml)
    if not out_dmi.exists():
        return toml, out_dmi, True, current_hash
    sidecar = _hash_sidecar_path(out_dmi)
    if not sidecar.exists():
        return toml, out_dmi, True, current_hash
    try:
        cached_hash = sidecar.read_text(encoding="ascii").strip()
    except OSError:
        return toml, out_dmi, True, current_hash
    if cached_hash != current_hash:
        return toml, out_dmi, True, current_hash
    return toml, out_dmi, False, current_hash


def _repack_one(args: tuple[Path, Path, str]) -> tuple[Path, str | None]:
    """Worker for the repack process pool.

    Repacks `toml` into `out_dmi`, writes the hash sidecar on success.
    Returns (toml, error_str_or_None).
    """
    toml, out_dmi, input_hash = args
    try:
        repack_mod.repack(toml, out_path=out_dmi)
        _hash_sidecar_path(out_dmi).write_text(input_hash, encoding="ascii")
        return toml, None
    except Exception as e:  # noqa: BLE001
        return toml, f"{type(e).__name__}: {e}"


def _gather_tomls(roots: list[Path], output_root: Path) -> list[Path]:
    tomls: list[Path] = []
    for r in roots:
        if not r.exists():
            continue
        # Don't descend into the output tree itself if it happens to live
        # under one of the source roots (e.g. icons/gen inside icons/).
        for toml in r.rglob("*.dmi.toml"):
            try:
                toml.relative_to(output_root)
                continue  # the toml is inside the output tree — skip
            except ValueError:
                pass
            tomls.append(toml)
    tomls.sort()
    return tomls


def run(roots: list[Path], output_root: Path) -> int:
    tomls = _gather_tomls(roots, output_root)
    if not tomls:
        return 0

    t0 = time.monotonic()

    # Pass 1: parallel dirty check (thread pool — bottleneck is file I/O,
    # hashing is cheap enough not to need processes).
    check_inputs = [(t, _output_dmi_path(t, output_root)) for t in tomls]
    dirty: list[tuple[Path, Path, str]] = []
    skipped = 0
    # 4x CPUs is a sweet spot for I/O bound work with cheap CPU per item.
    check_workers = (os.cpu_count() or 4) * 4
    with ThreadPoolExecutor(max_workers=check_workers) as pool:
        for toml, out_dmi, is_dirty, current_hash in pool.map(
            _check_one, check_inputs, chunksize=32
        ):
            if current_hash is None:
                continue  # missing PNG sibling — ignored
            if is_dirty:
                dirty.append((toml, out_dmi, current_hash))
            else:
                skipped += 1

    check_dt = time.monotonic() - t0

    # Pass 2: parallel repack (process pool — PIL is CPU bound, GIL
    # would serialise it in threads).
    repacked = 0
    failures: list[tuple[Path, str]] = []
    if dirty:
        # Sequential cost per item is ~150ms; below ~30 dirty items the
        # process-pool startup tax dominates and serial is faster.
        if len(dirty) < 30:
            for args in dirty:
                toml, err = _repack_one(args)
                if err:
                    failures.append((toml, err))
                else:
                    repacked += 1
        else:
            repack_workers = max(2, os.cpu_count() or 4)
            with ProcessPoolExecutor(max_workers=repack_workers) as pool:
                for toml, err in pool.map(_repack_one, dirty, chunksize=8):
                    if err:
                        failures.append((toml, err))
                    else:
                        repacked += 1

    dt = time.monotonic() - t0
    print(
        f"icon-repack: {repacked} regenerated into {output_root}, "
        f"{skipped} up-to-date, {len(failures)} failed in {dt:.1f}s "
        f"(dirty-check {check_dt:.1f}s)"
    )
    for p, msg in failures[:20]:
        print(f"  FAIL {p}: {msg}")
    if len(failures) > 20:
        print(f"  ... and {len(failures) - 20} more")
    return 1 if failures else 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("roots", nargs="+", type=Path, help="Source roots to scan for *.dmi.toml.")
    ap.add_argument(
        "--output",
        type=Path,
        required=True,
        help="Build-output root. Generated .dmi files land at <output>/<source-relative-path>.",
    )
    args = ap.parse_args()
    return run(args.roots, args.output.resolve())


if __name__ == "__main__":
    sys.exit(main())
