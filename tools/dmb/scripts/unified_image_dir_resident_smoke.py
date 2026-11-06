#!/usr/bin/env python3
"""Named ImageDir parity through one private resident dmbc."""
import argparse
import json
import re
from pathlib import Path

from unified_daemon_smoke import Smoke
from unified_derived_resident_transport_smoke import live


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("binary", "scratch-root", "repository"):
        parser.add_argument(f"--{name}", required=True, type=Path)
    args = parser.parse_args()
    smoke = Smoke(args.binary, args.scratch_root, args.repository)
    smoke.env.update(DMB_DAEMON_MAX_WORKERS="1", LOCALAPPDATA=str(smoke.root / "local"))
    fixture = args.repository / "tools/dmb/fixtures/unified_checks/image_dir_mixed_callable"
    try:
        root = smoke.root / "workspace"
        cache = smoke.root / "cache"
        cache.mkdir()
        (root / "code").mkdir(parents=True)
        (root / "tools/ci").mkdir(parents=True)
        manifest = root / "deepquarry.dme"
        source = b'#include "code/probe.dm"\n'
        manifest.write_bytes(source)
        (root / "code/probe.dm").write_bytes((fixture / "probe.dm").read_bytes())
        config = root / "tools/ci/lint_scopes.toml"
        config_bytes = b"[lint.image_dir_after_build.lists]\nexempt_files=[]\n# a\n"
        config.write_bytes(config_bytes)
        request = {"workspace_root": str(root), "cache_root": str(cache), "timeout_seconds": 60}

        def call(name, fields):
            path = smoke.root / f"{name}.json"
            path.write_text(json.dumps(fields), encoding="utf8")
            return smoke.run(["analyze-image-dir", str(path), "--report-batch"], success=False)

        def qualified(name):
            result = call(name, request)
            assert result.returncode == 1, (result.returncode, result.stderr)
            raw, body = result.stdout.split("\n", 1)
            terminal = json.loads(raw)
            assert set(terminal) == {"schema", "frame", "clean", "report"}, terminal
            assert terminal["schema"] == "native-analyze-image-dir-v1" and not terminal["clean"], terminal
            assert terminal["report"]["length"] == len(body.encode("utf8")), terminal
            assert re.fullmatch(r"[0-9a-f]{32}", terminal["report"]["hash"]), terminal
            assert set(terminal["frame"]) == {"semantic_revision", "source_revision", "policy_revision"}
            assert all(re.fullmatch(r"[0-9a-f]{32}", revision) for revision in terminal["frame"].values())
            assert body.encode("utf8") == (fixture / "expected.report").read_bytes()
            return terminal

        cold = qualified("cold")
        pid = live(smoke)
        assert qualified("warm") == cold and live(smoke) == pid
        config.write_bytes(config_bytes.replace(b"# a\n", b"# b\n"))
        changed_config = qualified("same-size-config-edit")
        assert changed_config["report"] == cold["report"]
        assert changed_config["frame"]["source_revision"] == cold["frame"]["source_revision"]
        assert changed_config["frame"]["semantic_revision"] == cold["frame"]["semantic_revision"]
        assert changed_config["frame"]["policy_revision"] != cold["frame"]["policy_revision"]
        config.write_bytes(config_bytes)
        manifest.write_bytes(b"#warn actual_named_image_dir_notice\n" + source)
        refused = call("notice", request)
        assert refused.returncode == 2 and not refused.stdout and "notice output has not been admitted" in refused.stderr, refused
        manifest.write_bytes(source)
        config.unlink()
        refused = call("missing-config", request)
        assert refused.returncode == 2 and not refused.stdout and refused.stderr, refused
        config.write_bytes(config_bytes)
        refused = call("foreign-role", dict(request, exclusions=[]))
        assert refused.returncode == 2 and not refused.stdout, refused
        assert qualified("recovered") == cold and live(smoke) == pid
        assert not manifest.with_suffix(".dmb").exists()
        print(json.dumps({"test": "named_image_dir_resident", "passed": True, "same_daemon_pid": pid}))
    finally:
        smoke.retire()


if __name__ == "__main__":
    main()
