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


def edit_sessions(edit, session_count):
    """Exact target assignment; absent assignment preserves all-session edits."""
    targets = edit.get("sessions", list(range(session_count)))
    if (not isinstance(targets, list) or not targets
            or any(type(index) is not int or not 0 <= index < session_count for index in targets)
            or len(set(targets)) != len(targets)):
        raise ValueError("edit sessions must be unique integer indices within the current source roster")
    return tuple(sorted(targets))


def session_edit_coverage(edits, session_count):
    assignments = [edit_sessions(edit, session_count) for edit in edits]
    if not any("sessions" in edit for edit in edits):
        result = required_edit_coverage(edits)
        result["classification"] = "six-worktree-byte-acceptance"
        return result
    observed = [set() for _ in range(session_count)]
    for edit, targets in zip(edits, assignments):
        label = "body" if edit.get("kind") == "body" else edit.get("structural_kind")
        if edit.get("kind") not in ("body", "structural") or label not in {"body", "newvar", "newproc", "default"}:
            raise ValueError("assigned edits require an explicit body or structural mutation label")
        for index in targets:
            observed[index].add(label)
    required = {"body", "newvar", "newproc", "default"}
    full = all(required <= labels for labels in observed)
    if not full:
        body = {index for index, labels in enumerate(observed) if "body" in labels}
        structural = {index for index, labels in enumerate(observed) if labels - {"body"}}
        unchanged = {index for index, labels in enumerate(observed) if not labels}
        if not unchanged or not any(a != b for a in body for b in structural):
            raise ValueError("isolation probe requires distinct body/structural sessions and an unchanged session")
    return {"classification": "six-worktree-byte-acceptance" if full else "six-session-isolation-probe",
            "per_session": [sorted(labels) for labels in observed],
            "required": sorted(required),
            "scope": "exact edit assignments; every session requires an independent fresh byte oracle; no runtime claim"}


def daemon_reserve(job_bytes, sampled_bytes):
    """Leave aggregate headroom; pressure remains sampled, not a peak bound."""
    aggregate = min(job_bytes, sampled_bytes)
    if aggregate < 512 * 1024 * 1024:
        raise ValueError("six-session memory budget must allow at least 512 MiB for daemon and clients")
    return min(aggregate // 2, 32 * 1024 ** 3)
