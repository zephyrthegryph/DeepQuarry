"""Cohort-local raw inspector evidence reuse; admissions are never cached."""
import hashlib
import json
from pathlib import Path


def digest(path):
    value = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def key(*, inspector_sha256, expected_dmb_sha256, actual_dmb_sha256,
        actual_rsc_sha256, snapshot_id, configuration_sha256):
    # Include RSC conservatively even though the inspector consumes only DMB.
    return {"schema_version": 1, "command": "structural-diff-four-positional-v1",
            "signature_algorithm": "md5-length-framed-v1",
            "inspector_sha256": inspector_sha256,
            "expected_dmb_sha256": expected_dmb_sha256,
            "actual_dmb_sha256": actual_dmb_sha256,
            "actual_rsc_sha256": actual_rsc_sha256,
            "snapshot_id": snapshot_id,
            "semantic_configuration_sha256": configuration_sha256}


def key_digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


class Reports:
    """One invocation-local registry, holding small descriptors only."""
    def __init__(self):
        self._reports = {}

    def remember(self, identity, report, origin):
        path = Path(report).resolve()
        value = {"identity": dict(identity), "report": str(path),
                 "report_sha256": digest(path), "origin_run": str(origin)}
        self._reports[key_digest(identity)] = value

    def lookup(self, identity):
        descriptor = self._reports.get(key_digest(identity))
        if descriptor is None:
            return None
        if descriptor["identity"] != identity:
            raise ValueError("structural reuse identity mismatch")
        path = Path(descriptor["report"])
        before = digest(path)
        if before != descriptor["report_sha256"]:
            raise ValueError("structural reuse report hash mismatch")
        value = json.loads(path.read_text(encoding="utf-8"))
        if digest(path) != before:
            raise ValueError("structural reuse report changed while loading")
        if (value.get("schema_version") != identity["schema_version"]
                or value.get("snapshot_id") != identity["snapshot_id"]
                or value.get("signature_algorithm") != identity["signature_algorithm"]
                or value.get("traversal_complete") is not True
                or value.get("tool_complete") is not True):
            raise ValueError("structural reuse report contract mismatch")
        return value, dict(descriptor)
