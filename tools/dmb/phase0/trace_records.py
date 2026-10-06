"""Recognize the preserved compiler's named timing records exactly."""
import re


STAGES = (
    "patch planning", "patch publication", "retained input validation",
    "project discovery/preprocessing", "source hashing", "active map loading",
    "resource request scan", "resource byte hashing", "map/resource fingerprinting",
    "input revalidation", "artifact CAS lookup", "compiler", "artifact CAS write",
    "generation publication",
)
TIMING = re.compile(r"dm-compiled (?:" + "|".join(map(re.escape, STAGES)) + r"): \d+\.\d{3}s$")


def is_build_trace(line):
    return line.startswith("DM_BUILD_TRACE") or bool(TIMING.fullmatch(line.rstrip("\r\n")))
