"""Preflight captured Verdigris authority; ABI equality alone is not source proof."""
import re
from pathlib import Path
from recover_iteration_source import absolute_nonreparse, regular


def matching_abi(bindings, rust):
    dm = re.findall(r'^#define VERDIGRIS_ABI "([0-9a-f]+)"', bindings, re.MULTILINE)
    native = re.findall(r'pub const ABI: &str = "([0-9a-f]+)";', rust)
    if len(dm) != 1 or len(native) != 1:
        raise ValueError("captured Verdigris requires exactly one DM and Rust ABI declaration")
    if dm[0] != native[0]:
        raise ValueError(f"captured Verdigris ABI mismatch: DM={dm[0]} Rust={native[0]}; recapture coherent sources")
    return dm[0]


def preflight(root):
    source = absolute_nonreparse(Path(root) / "source")
    bindings = source / "code/__defines/verdigris/_bindings.dm"
    rust = source / "verdigris/ffi/src/abi.rs"
    for file in (bindings, rust):
        absolute_nonreparse(file)
        regular(file)
        if file.stat().st_size > 1024 * 1024:
            raise ValueError("captured ABI declaration exceeds preflight bound")
    return matching_abi(bindings.read_text(encoding="utf-8-sig"), rust.read_text(encoding="utf-8-sig"))
