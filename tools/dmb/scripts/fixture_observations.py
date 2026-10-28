"""Read-only observation guards for independent compiler/checker fixtures."""
import hashlib
import json


def fixture_inputs(root):
    """Fixture-directory bytes/roster guard; not an inferred include closure."""
    return {path.relative_to(root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(root.rglob("*"))
            if path.is_file() and path.suffix.lower() in (".dm", ".dme", ".toml")}


def require_unchanged(before, after, label="fixture"):
    if before != after:
        changed = sorted(key for key in before.keys() | after.keys()
                         if before.get(key) != after.get(key))
        raise ValueError(f"{label} inputs changed during observation: {changed[:8]}")


def observation_digest(inputs):
    return hashlib.sha256(json.dumps(inputs, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
