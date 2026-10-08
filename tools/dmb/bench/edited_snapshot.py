"""Authenticate one private captured-source derivative; never edit live sources."""
import json
from pathlib import Path


def authenticate(h, scenario, parent_journal, byond_pin):
    if scenario.get("edits") or not parent_journal:
        raise ValueError("cold-body-edit requires immutable parent journal and no live edits")
    receipt = Path(scenario["variant_receipt"]).resolve()
    if h.sha(receipt) != scenario["variant_receipt_sha256"]:
        raise ValueError("edited receipt hash mismatch")
    variant = json.loads(receipt.read_bytes())
    if variant.get("schema") != 1 or variant.get("physical_source_changed") is not False:
        raise ValueError("edited source must be a captured private derivative")
    parent = Path(parent_journal).resolve()
    journal = Path(scenario["input_journal"]).resolve()
    if journal == parent or Path(variant["original_snapshot"]).resolve() != parent or Path(variant["snapshot"]).resolve() != journal:
        raise ValueError("edited journal provenance does not match parent")
    pinned = {receipt: scenario["variant_receipt_sha256"]}
    for folder, key in ((parent, "original_index"), (journal, "index")):
        for filename, suffix in (("index.json", "sha256"), ("index.hash", "hash_sha256")):
            path = folder / filename
            digest = variant[key + "_" + suffix]
            if h.sha(path) != digest:
                raise ValueError("edited journal index pin mismatch")
            pinned[path] = digest
    overlay_path = receipt.parent / "overlay.json"
    if h.sha(overlay_path) != variant["overlay_sha256"]:
        raise ValueError("edited overlay pin mismatch")
    pinned[overlay_path] = variant["overlay_sha256"]
    overlay = json.loads(overlay_path.read_bytes())
    old = json.loads((parent / "index.json").read_bytes())
    new = json.loads((journal / "index.json").read_bytes())
    if set(old) != set(new) or old["negative"] != new["negative"] or old["folders"] != new["folders"] or set(old["files"]) != set(new["files"]):
        raise ValueError("edited journal changed capture closure")
    changed = [path for path in old["files"] if old["files"][path] != new["files"][path]]
    if changed != [overlay["canonical_path"]]:
        raise ValueError("edited journal must change exactly its declared source")
    source = changed[0]
    old_stamp, old_hash = old["files"][source]
    new_stamp, new_hash = new["files"][source]
    if (str(old_hash) != overlay["old_xxh3_128"] or str(new_hash) != overlay["new_xxh3_128"]
            or old_stamp["size"] != new_stamp["size"] or new_stamp["size"] != overlay["byte_length"]
            or new_stamp.get("file_id") is not None):
        raise ValueError("edited source identity/derived stamp mismatch")
    before_path = parent / "payloads" / format(old_hash, "032x")
    after_path = journal / "payloads" / format(new_hash, "032x")
    for path, key in ((before_path, "old_payload_sha256"), (after_path, "new_payload_sha256")):
        if h.sha(path) != overlay[key]:
            raise ValueError("edited source payload hash mismatch")
        pinned[path] = overlay[key]
    before, after = before_path.read_bytes(), after_path.read_bytes()
    needle, replacement = overlay["before"].encode(), overlay["after"].encode()
    if not needle or before.count(needle) != 1 or before.replace(needle, replacement) != after or len(before) != len(after):
        raise ValueError("edited payload must be one exact same-length literal replacement")
    if (byond_pin.get("snapshot_id") != variant["index_sha256"]
            or byond_pin.get("source_variant_sha256") != scenario["variant_receipt_sha256"]):
        raise ValueError("BYOND must independently pin this exact edited journal and provenance")
    return {"journal": journal, "snapshot_id": variant["index_sha256"], "pinned": pinned,
            "provenance": {"variant_receipt": str(receipt), "variant_receipt_sha256": scenario["variant_receipt_sha256"],
                           "parent_snapshot_id": variant["original_index_sha256"], "overlay_sha256": variant["overlay_sha256"],
                           "measurement_scope": "edited_source_cold_trace_not_incremental_latency"}}
