#!/usr/bin/env python3
"""Bounded IPC smoke; caller supplies a shared/test_scratch.rs-owned directory.

Run through the ignored `unified_daemon_smoke` Rust integration test after the
private compiler is built. This script never builds/publishes a compiler, edits
tracked fixtures, allocates its own cache root, or retires another namespace.
It verifies only the explicitly migrated checker/untyped endpoints.

Uses explicit --request-timeout-seconds budgets. Compile, preparation and
query work inherit cooperative server deadlines; clients
also have wall-clock limits. Retirement drains only the owned namespace. These
are checkpoint-based cancellation bounds, not a process-kill watchdog.
"""
from __future__ import annotations

import argparse
import ctypes
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
import uuid

POLICY_SOURCE = "/datum/ipc_probe\n    var/saved\n    proc/assign(datum/value)\n        saved = value\n"


def request(project: Path, engine: Path, pins: dict, questions: list) -> dict:
    value = {"timeout_seconds": 30, "project": str(project), "defines": {},
             "engine_template": str(engine), "bootstrap_catalog": True,
             "expected_revision": pins["semantic_revision"],
             "expected_source_revision": pins["source_revision"],
             "queries": [], "source_queries": questions}
    if pins.get("policy_revision") is not None:
        value["expected_policy_revision"] = pins["policy_revision"]
    return value



def json_rows(text: str) -> list[dict]:
    return [json.loads(line) for line in text.splitlines() if line.strip()]


def assert_reply(reply: dict, pins: dict) -> list[dict]:
    assert reply["revision"] == pins["semantic_revision"], reply
    assert reply["source_revision"] == pins["source_revision"], reply
    assert reply["complete"] is False, "bounded fixture endpoint claimed complete coverage"
    assert reply.get("policy_revision") == pins.get("policy_revision"), "foreign policy reply"
    rows = json_rows(reply["jsonl"])
    for row in rows:
        if row["row"] in {"source_native_untyped_fixture", "source_native_named_rule", "source_native_configured_checker", "source_native_raw_policy_fixture", "source_native_configured_control_batch"}:
            assert row.get("policy_revision") == pins.get("policy_revision"), "foreign raw-policy row"
    return rows


def compiled_pins(reply: dict) -> dict:
    assert reply["snapshot_outcome"] == "published", reply
    assert reply["last_request_outcome"] == "published", reply
    assert reply["publication_pair"] is not None, "Compile did not publish an indivisible pair"
    pins = {"semantic_revision": reply["revision"], "source_revision": reply["source_revision"],
            "policy_revision": reply.get("policy_revision")}
    assert all(isinstance(pin, str) and re.fullmatch(r"[0-9a-fA-F]{32}", pin)
               for pin in pins.values()), "compiled query snapshot did not expose exact pins"
    return pins


def assert_findings(rows: list[dict], present: bool, checker_present: bool | None = None) -> None:
    untyped = [row for row in rows if row["row"] == "source_native_untyped_fixture"]
    checker = [row for row in rows if row["row"] == "source_native_checker_fixture"]
    assert len(untyped) == len(checker) == 1, rows
    assert untyped[0]["full_policy_parity"] is False
    assert checker[0]["full_checker_parity"] is False
    findings = untyped[0]["findings"]
    if checker_present is None:
        checker_present = present
    if present:
        assert len(findings) == 1, findings
        assert findings[0]["identity"] == "/datum/ipc_probe::saved", findings
        assert findings[0]["rule"] == "typed", findings
        assert Path(findings[0]["file"]).name == "smoke_policy.dm", findings
    else:
        assert findings == [], findings
    if checker_present:
        assert len(checker[0]["diagnostics"]) == 1, checker
        assert checker[0]["diagnostics"][0]["family"] == "ambiguous_not_bitwise"
    else:
        assert checker[0]["diagnostics"] == [], checker


def named_questions(project: Path, ordinal: int, control_ordinal: int | None = None) -> list[dict]:
    questions = [
        {"NativeNamedRule": {"root": str(project.parent), "lint": "base_vars",
                             "rule": "records_data_only", "configuration": str(project.parent / "lint_scopes.toml")}},
        {"NativeConfiguredChecker": {"ordinal": ordinal, "family": "ambiguous_not_bitwise",
                                     "environment": str(project), "configuration": None}},
        {"NativeRawPolicyFixture": {"root": str(project.parent), "configuration": str(project.parent / "optional.toml"), "lints": ["scheduler"]}},
    ]
    if control_ordinal is not None:
        questions.append({"NativeConfiguredControlBatch": {"ordinal": control_ordinal,
            "families": ["if_condition_determinate", "control_condition_static", "unreachable_code"],
            "environment": str(project), "configuration": None}})
    return questions


def assert_named_findings(rows: list[dict]) -> None:
    named = [row for row in rows if row["row"] == "source_native_named_rule"]
    configured = [row for row in rows if row["row"] == "source_native_configured_checker"]
    assert len(named) == len(configured) == 1, rows
    assert named[0]["full_lint_parity"] is False
    assert named[0]["coverage"] == "captured_compiled_declarations"
    findings = named[0]["findings"]
    assert len(findings) == 1, findings
    assert findings[0]["rule"] == "records_data_only" and findings[0]["line"] == 2, findings
    assert Path(findings[0]["rel"]).name == "smoke_records.dm", findings
    assert all(findings[0][key] == "" for key in ["msg", "key", "ident"]), findings
    row = configured[0]
    assert row["full_checker_parity"] is False
    assert row["configuration_schema"] == "complete_pinned_checker_schema"
    assert row["configuration_present"] is True and row["configuration_explicit"] is False
    assert len(row["diagnostics"]) == 1, row
    assert row["diagnostics"][0]["family"] == "ambiguous_not_bitwise"
    assert row["diagnostics"][0]["severity"] == "hint", "captured config was not applied"


def assert_raw_findings(rows: list[dict]) -> None:
    raw = [row for row in rows if row["row"] == "source_native_raw_policy_fixture"]
    assert len(raw) == 1, rows
    row = raw[0]
    assert row["full_policy_parity"] is False and row["baseline_applied"] is False
    assert row["configuration_scope"] == "proven_missing_configuration"
    assert row["requested_lints"] == ["scheduler"]
    assert row["scope"] == "explicit_captured_files"
    assert len(row["results"]) == 1 and row["results"][0]["name"] == "scheduler"
    sites = row["results"][0]["sites"]
    assert len(sites) == 1 and sites[0]["line"] == 2, sites
    assert Path(sites[0]["rel"]).name == "raw_probe.dm", sites


def assert_control_batch(rows: list[dict]) -> None:
    batches = [row for row in rows if row["row"] == "source_native_configured_control_batch"]
    assert len(batches) == 1, rows
    row = batches[0]
    assert row["full_checker_parity"] is False
    assert row["ordering"] == "primary_control_event_order" and row["flow_reuse"] == "request_local_union"
    diagnostics = row["diagnostics"]
    assert [d["family"] for d in diagnostics] == ["control_condition_static", "if_condition_determinate"], diagnostics
    assert [d["severity"] for d in diagnostics] == ["hint", "warning"], diagnostics
    assert diagnostics[0]["expanded_span"] == diagnostics[1]["expanded_span"]


class Smoke:
    def __init__(self, binary: Path, scratch: Path, repository: Path):
        self.binary = binary.resolve(strict=True)
        if "dmb-bin" in (part.lower() for part in self.binary.parts):
            raise ValueError("pass a freshly built private compiler, not a published binary")
        self.root = scratch.resolve(strict=True)
        if not self.root.is_dir() or not re.fullmatch(r"run-[0-9]+-[0-9]+", self.root.parent.name):
            raise ValueError("scratch must be a dir() child issued by shared/test_scratch.rs")
        if list(self.root.iterdir()):
            raise ValueError("scratch child must be fresh and empty")
        self.repository = repository.resolve(strict=True)
        self.namespace = f"unified-smoke-{os.getpid()}-{uuid.uuid4().hex[:12]}"
        self.env = os.environ.copy()
        self.env.update(DMB_DAEMON_NAMESPACE=self.namespace,
                        DMB_DAEMON_DIR=str(self.root / "daemon"),
                        DMB_CACHE_DIR=str(self.root / "cache"),
                        DMB_DAEMON_IDLE_EXIT_SECS="60", DQ_PRIORITY="low")
        self.env.pop("DMB_DAEMON_AUTOSTART", None)
        self.env.pop("DMB_PREPARE_TIMEOUT_SECONDS", None)
        self.env.pop("DMB_UNIFIED_ANALYSIS", None)  # explicit public request must suffice
        self.deadline = time.monotonic() + 240
        self.calls = []
        self.policy_intent = None
        if os.name == "nt":
            # The Python coordinator and every CLI child remain below normal.
            kernel = ctypes.windll.kernel32
            kernel.GetCurrentProcess.restype = ctypes.c_void_p
            kernel.SetPriorityClass.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
            if not kernel.SetPriorityClass(kernel.GetCurrentProcess(), 0x4000):
                raise OSError("could not lower smoke coordinator priority")

    def run(self, args: list[str], *, success: bool = True, cleanup: bool = False,
            cleanup_deadline: float | None = None) -> subprocess.CompletedProcess:
        if args and args[0] == "compile" and os.environ.get("DQ_UNIFIED_IPC_PIPE_PROBE") == "1":
            self.probe_pipe_lifetime(args)
        now = time.monotonic()
        end = (cleanup_deadline if cleanup_deadline is not None else now + 15) if cleanup else self.deadline
        remaining = end - now
        if remaining <= 0:
            raise TimeoutError("owned daemon cleanup budget exhausted" if cleanup else "smoke request budget exhausted")
        timeout = min(15 if cleanup else 90, remaining)
        flags = subprocess.BELOW_NORMAL_PRIORITY_CLASS if os.name == "nt" else 0
        result = subprocess.run([str(self.binary), *args], cwd=self.root, env=self.env,
                                text=True, encoding="utf-8", errors="replace", capture_output=True,
                                timeout=timeout, creationflags=flags)
        index = len(self.calls)
        (self.root / f"call-{index}.stdout").write_text(result.stdout, encoding="utf-8")
        (self.root / f"call-{index}.stderr").write_text(result.stderr, encoding="utf-8")
        self.calls.append({"args": args, "returncode": result.returncode})
        if success and result.returncode:
            raise AssertionError(f"private daemon call failed ({result.returncode}): {result.stderr}")
        return result

    def probe_pipe_lifetime(self, args: list[str]) -> None:
        # Diagnostic only: separate process lifetime from EOF on captured pipes.
        # Do not lengthen namespace idle time or pretend a live CLI has exited.
        flags = subprocess.BELOW_NORMAL_PRIORITY_CLASS if os.name == "nt" else 0
        started = time.monotonic()
        child = subprocess.Popen([str(self.binary), *args], cwd=self.root, env=self.env,
                                 text=True, encoding="utf-8", errors="replace",
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, creationflags=flags)
        evidence = {"namespace": self.namespace, "pid": child.pid}
        stdout = stderr = ""
        try:
            try:
                evidence["returncode"] = child.wait(timeout=8)
                evidence["process_exit_seconds"] = time.monotonic() - started
                try:
                    stdout, stderr = child.communicate(timeout=1)
                    evidence["pipe_eof_after_exit"] = True
                except subprocess.TimeoutExpired:
                    evidence["pipe_eof_after_exit"] = False
            except subprocess.TimeoutExpired:
                evidence["process_still_running_after_8s"] = True
            # Only this namespace is drained. No process termination, PID kill or
            # default/shared daemon action is used to release remaining handles.
            self.retire()
            try:
                stdout, stderr = child.communicate(timeout=3)
                evidence["returncode_after_owned_retire"] = child.returncode
                evidence["pipe_eof_after_owned_retire"] = True
            except subprocess.TimeoutExpired:
                evidence["pipe_eof_after_owned_retire"] = False
            evidence["total_seconds"] = time.monotonic() - started
        finally:
            (self.root / "pipe-lifetime.json").write_text(json.dumps(evidence, indent=2), encoding="utf-8")
            (self.root / "pipe-lifetime.stdout").write_text(stdout, encoding="utf-8")
            (self.root / "pipe-lifetime.stderr").write_text(stderr, encoding="utf-8")
        raise RuntimeError("explicit pipe-lifetime probe completed (not a smoke pass): " + json.dumps(evidence))

    def prepare(self, project: Path, engine: Path) -> dict:
        args = ["prepare-query", str(project), "--engine-template", str(engine),
                "--bootstrap-catalog", "--workers", "2", "--exact-inputs",
                "--request-timeout-seconds", "45"]
        if self.policy_intent is not None:
            args.extend(["--policy-inputs-json", json.dumps(self.policy_intent)])
        result = self.run(args)
        rows = [row for row in json_rows(result.stdout) if row.get("row") == "query_prepared"]
        assert len(rows) == 1 and rows[0]["retained"] is True, result.stdout
        return rows[0]

    def compile_and_discover(self, project: Path, engine: Path) -> dict:
        args = ["compile", str(project), "--engine-template", str(engine),
                "--bootstrap-catalog", "--workers", "2", "--exact-inputs",
                "--request-timeout-seconds", "45", "--output-store", str(self.root / "pairs"),
                "--artifact-directory", str(self.root / "artifacts")]
        if self.policy_intent is not None:
            args.extend(["--policy-inputs-json", json.dumps(self.policy_intent)])
        capture_started = time.monotonic()
        self.run(args)
        self.compile_capture_seconds = time.monotonic() - capture_started
        # Compile's cooperative request budget is 45s; its captured CLI streams
        # must close without waiting for this namespace's 60s idle retirement.
        assert self.compile_capture_seconds < 50, "Compile capture waited for daemon lifetime instead of CLI lifetime"
        assert (self.root / "artifacts" / project.with_suffix(".dmb").name).is_file(), "Compile did not install its DMB"
        assert (self.root / "artifacts" / project.with_suffix(".rsc").name).is_file(), "Compile did not install its RSC"
        # Discovery asks no policy question and carries no assumed pin. Its reply
        # identifies the exact source/policy owners published by this compile.
        discovery = {"timeout_seconds": 30, "project": str(project), "defines": {},
                     "engine_template": str(engine), "bootstrap_catalog": True,
                     "expected_revision": None, "expected_source_revision": None,
                     "queries": [], "source_queries": []}
        path = self.root / f"discover-{len(self.calls)}.json"
        path.write_text(json.dumps(discovery), encoding="utf-8")
        result = self.run(["query", str(path)])
        return compiled_pins(json.loads(result.stdout))

    def query(self, project: Path, engine: Path, pins: dict, questions: list, success: bool = True):
        path = self.root / f"query-{len(self.calls)}.json"
        path.write_text(json.dumps(request(project, engine, pins, questions)), encoding="utf-8")
        result = self.run(["query", str(path)], success=success)
        return assert_reply(json.loads(result.stdout), pins) if success else result

    def observe(self, project: Path, engine: Path, pins: dict) -> list[dict]:
        pages = self.query(project, engine, pins, [{"BodyContextsPage": {"start": 0, "limit": 128}}])
        assert len(pages) == 1 and pages[0]["next_cursor"] is None, pages
        first = [body for body in pages[0]["items"]
                 if Path(body["source"]["path"]).name == "first.dm" and body["source"]["line"] == 1]
        assert len(first) == 1, pages
        return self.query(project, engine, pins, [
            {"NativeUntypedFixture": {"root": str(project.parent)}},
            {"NativeCheckerFixture": {"ordinal": first[0]["ordinal"], "severity": "warning"}},
        ])

    def observe_named(self, project: Path, engine: Path, pins: dict) -> list[dict]:
        pages = self.query(project, engine, pins, [{"BodyContextsPage": {"start": 0, "limit": 128}}])
        assert len(pages) == 1 and pages[0]["next_cursor"] is None, pages
        first = [body for body in pages[0]["items"]
                 if Path(body["source"]["path"]).name == "first.dm" and body["source"]["line"] == 1]
        assert len(first) == 1, pages
        control = [body for body in pages[0]["items"]
                   if Path(body["source"]["path"]).name == "smoke_records.dm" and body["source"]["line"] == 7]
        assert len(control) == 1, pages
        return self.query(project, engine, pins, named_questions(project, first[0]["ordinal"], control[0]["ordinal"]))

    def execute(self) -> None:
        fixture = self.repository / "tools/dmb/fixtures/unified_checks"
        # Keep request/result logs and published artifacts outside observed source
        # folders, so policy-only invalidation cannot pass due to smoke log churn.
        source_root = self.root / "source"
        source_root.mkdir()
        project = source_root / "bitwise.dme"
        for name in ["bitwise.dme", "first.dm", "second.dm"]:
            shutil.copyfile(fixture / name, source_root / name)
        project.write_bytes(project.read_bytes() + b'\n#include "code/smoke_policy.dm"\n')
        project.write_bytes(project.read_bytes() + b'#include "smoke_records.dm"\n')
        (source_root / "smoke_records.dm").write_text(
            "/datum/record\n    proc/rebuild()\n        return 1\n    proc/get_value()\n        return 1\n\n/proc/smoke_control()\n    if(1)\n        return 1\n    return 2\n", encoding="utf-8")
        (source_root / "lint_scopes.toml").write_text(
            "[lint.base_vars.lists]\nrecord_accessor_prefixes=['get_']\n", encoding="utf-8")
        (source_root / "SpacemanDMM.toml").write_text(
            "[diagnostics]\nambiguous_not_bitwise='hint'\ncontrol_condition_static='hint'\nif_condition_determinate='warning'\nunreachable_code='off'\n", encoding="utf-8")
        raw_dir = source_root / "code"
        raw_dir.mkdir()
        raw_probe = raw_dir / "raw_probe.dm"
        # This is explicitly captured raw policy input, not compiled executable
        # code; it proves the named raw-only cohort without adding scheduler debt.
        raw_probe.write_text("/datum/raw_probe/proc/work()\n    sleep(1)\n", encoding="utf-8")
        # The original untyped policy deliberately selects declarations under
        # code/. This positive probe must be in scope; do not weaken policy.
        policy = raw_dir / "smoke_policy.dm"
        policy.write_text(POLICY_SOURCE, encoding="utf-8", newline="\n")
        marker = source_root / "policy_marker.dm"
        marker.write_text("// explicit noncompiled schema scope\n", encoding="utf-8")
        search = source_root / "search"
        search.mkdir()
        self.policy_intent = {"files": [
            {"path": str(marker), "role": "dm_source", "required": True},
            {"path": str(raw_probe), "role": "dm_source", "required": True},
            {"path": str(source_root / "lint_scopes.toml"), "role": "configuration", "required": True},
            {"path": str(source_root / "SpacemanDMM.toml"), "role": "configuration", "required": True},
            {"path": str(source_root / "optional.toml"), "role": "configuration", "required": False},
        ], "search_folders": [str(search)]}
        original = (source_root / "first.dm").read_bytes()
        engine = self.repository / "tools/dmb/fixtures/native_template.bin"
        descriptor = json.loads(self.run(["--daemon-endpoint-json"]).stdout)
        assert descriptor["namespace"] == self.namespace, descriptor
        compiled = self.compile_and_discover(project, engine)
        # Both migrated policies must answer against the actual compiled owner,
        # before any nonpublishing preparation can replace that source snapshot.
        assert_findings(self.observe(project, engine, compiled), True)
        named_compiled = self.observe_named(project, engine, compiled)
        assert_named_findings(named_compiled)
        assert_raw_findings(named_compiled)
        assert_control_batch(named_compiled)
        # Still the same compiled owner: a discovery-less policy read may not
        # omit the exact capture pin merely because its source pin is current.
        no_policy = {key: value for key, value in compiled.items() if key != "policy_revision"}
        rejected = self.query(project, engine, no_policy, named_questions(project, 0), success=False)
        assert rejected.returncode != 0 and "policy" in rejected.stderr.lower()

        first = self.prepare(project, engine)
        assert first.get("policy_revision") is not None, "explicit capture omitted policy revision"
        initial = self.observe(project, engine, first)
        assert_findings(initial, True)
        # Same revisions use the same daemon/query ownership without preparing.
        assert self.observe(project, engine, first) == initial
        # Policy-only edit leaves the compiled source pin unchanged, but must
        # retract the finding under the newly captured noncompiled schema.
        marker.write_text("SCHEMA(/datum/ipc_probe, saved, schema_msg())\n", encoding="utf-8")
        policy_changed = self.prepare(project, engine)
        assert policy_changed["source_revision"] == first["source_revision"]
        assert policy_changed["policy_revision"] != first["policy_revision"]
        stale = self.query(project, engine, first, [{"NativeUntypedFixture": {"root": str(source_root)}}], success=False)
        assert stale.returncode != 0 and "policy" in stale.stderr.lower(), "stale policy pin was not refused"
        no_policy = {key: value for key, value in policy_changed.items() if key != "policy_revision"}
        unpinned = self.query(project, engine, no_policy, [{"NativeUntypedFixture": {"root": str(source_root)}}], success=False)
        assert unpinned.returncode != 0 and "policy" in unpinned.stderr.lower(), "missing policy pin was not refused"
        assert_findings(self.observe(project, engine, policy_changed), False, True)
        marker.write_text("// explicit noncompiled schema scope\n", encoding="utf-8")
        policy.write_text(POLICY_SOURCE.replace("saved = value", "saved = 1"), encoding="utf-8", newline="\n")
        assert b"return !x & y" in original
        (source_root / "first.dm").write_bytes(original.replace(b"return !x & y", b"return x & y", 1))
        edited = self.prepare(project, engine)
        assert edited["source_revision"] != first["source_revision"], "edit did not invalidate source revision"
        old = self.query(project, engine, first, [{"NativeUntypedFixture": {"root": str(source_root)}}], success=False)
        assert old.returncode != 0, "old revision unexpectedly admitted after body edit"
        assert_findings(self.observe(project, engine, edited), False)
        policy.write_text(POLICY_SOURCE, encoding="utf-8", newline="\n")
        (source_root / "first.dm").write_bytes(original)
        restored = self.prepare(project, engine)
        assert_findings(self.observe(project, engine, restored), True)
        (self.root / "evidence.json").write_text(json.dumps({
            "namespace": self.namespace, "compiler_identity": descriptor["compiler_identity"],
            "compiled": compiled, "compiled_client_capture_seconds": self.compile_capture_seconds, "compiled_named_findings": named_compiled, "initial": first, "policy_only": policy_changed, "edited": edited, "restored": restored,
            "bounded_policy_only": True, "calls": self.calls,
        }, indent=2), encoding="utf-8")

    def retire(self) -> None:
        # Never PID-kill or retire the default/published daemon. Only the exact
        # unique namespace created above is sent the normal draining request.
        end = time.monotonic() + 15
        while True:
            result = self.run(["--daemon-retire"], cleanup=True, cleanup_deadline=end)
            if "absent" in result.stdout:
                return
            remaining = end - time.monotonic()
            if remaining <= 0:
                raise RuntimeError("owned daemon did not drain within cleanup budget")
            time.sleep(min(0.2, remaining))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--scratch-root", type=Path, required=True)
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[3])
    args = parser.parse_args()
    smoke = Smoke(args.binary, args.scratch_root, args.repository)
    try:
        smoke.execute()
    finally:
        smoke.retire()
    print("unified daemon IPC smoke passed (bounded checker/untyped coverage)")


if __name__ == "__main__":
    main()
