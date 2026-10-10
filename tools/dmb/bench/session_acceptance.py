"""Explicit scenario admission; labels describe edits, never certify outputs."""

def required_edit_coverage(edits):
    required = {"body", "newvar", "newproc", "default"}
    observed = set()
    for edit in edits:
        if edit.get("kind") == "body":
            observed.add("body")
        elif edit.get("kind") == "structural":
            observed.add(edit.get("structural_kind"))
    missing = required - observed
    if missing:
        raise ValueError("six-session acceptance requires explicit edits: " + ", ".join(sorted(missing)))
    return {"required": sorted(required), "observed": sorted(item for item in observed if item),
            "scope": "requested mutation labels; each of six sessions must independently pass fresh byte oracles"}


def bounded_policy(total_workers, request_workers, job_memory_mib, sampled_bytes=None):
    if not 1 <= total_workers <= 8 or not 1 <= request_workers <= total_workers:
        raise ValueError("request workers must fit explicit total worker budget 1..8")
    if not 1 <= job_memory_mib <= 32768:
        raise ValueError("job memory must be 1..32768 MiB")
    job_bytes = job_memory_mib * 1024 * 1024
    if sampled_bytes is not None and not 1 <= sampled_bytes <= job_bytes:
        raise ValueError("sampled owned memory budget must fit configured job cap")
    return job_bytes
