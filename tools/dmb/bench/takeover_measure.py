"""Release-profile incremental measurement of the native compiler on DeepQuarry.

Usage (from anywhere; Windows, E: drive):
    python tools/dmb/bench/takeover_measure.py --worktree E:/projects/dq-wt/<name> \
        [--workers 8] [--skip-build] [--compiler PATH] [--out SUMMARY.json]

What it does, in one command:
  1. Builds dmbc in the plain `release` profile of <worktree>/tools/dmb (thin LTO, mimalloc,
     no allocation-counting feature, no opt-level override) under the machine cargo slot,
     into E:/dq-cache/dmb-takeover/measure/target (shared across runs; incremental).
  2. Runs bench/native-iteration.py from that worktree with --byte-oracles-only against the
     recovered DeepQuarry baseline source and the body + leaf-variable edits
     (scenarios: fresh cold oracle, retained initial, unchanged, body edit, leaf var edit).
     Fresh-vs-retained DMB/RSC byte equality is checked by the harness.
  3. Writes a JSON summary (per-request wall, per-stage seconds, peak commit, eviction signals)
     and prints it.
Inputs are the pinned ones used by the 20261012 runs under E:/dq-cache/dmb-native-v2.
Takes ~10-30 min and ~15 GB of E: disk (run root under E:/dq-cache/dmb-native-iterations).
"""
import argparse, json, os, subprocess, sys, time
from pathlib import Path

BASE = "E:/dq-cache/dmb-native-v2/recovered-baseline-20261010"
EDITS = "E:/dq-cache/dmb-native-v2/integration-gates/iteration-edits-body-leaf-var-20261011.json"
INSPECTOR = "E:/dq-cache/dmb-native-v2/frozen-build/20261011-e423001c58-inspector-opt0.exe"
TARGET = "E:/dq-cache/dmb-takeover/measure/target"
SLOTS = "E:/projects/CHOMPStation2/tools/dq_machine_slots.sh"


def build(worktree):
    env = dict(os.environ, CARGO_HOME="E:/dq-cache/dmb-native-v2/cargo-home", CARGO_TARGET_DIR=TARGET)
    cmd = ["bash", SLOTS, "run", "cargo", "--label", "dmb-measure", "--", "E:/cargo/bin/cargo.exe",
           "build", "--release", "--locked", "--offline", "-p", "dmbc", "--bin", "dmbc"]
    subprocess.run(cmd, cwd=worktree / "tools/dmb", env=env, check=True)
    return TARGET + "/release/dmbc.exe"


def flat(obj, prefix=""):
    out = {}
    if isinstance(obj, dict):
        for k, v in obj.items():
            out.update(flat(v, f"{prefix}{k}."))
    elif isinstance(obj, (int, float)) and not isinstance(obj, bool):
        out[prefix[:-1]] = obj
    return out


def stage_lines(root, ordinal):
    """Parse the compiler's `native stages:` / `native compile:` summary lines (seconds)."""
    import re
    out = {}
    log = Path(root) / str(ordinal) / "retained" / "stderr.log"
    if log.exists():
        for line in log.read_text(errors="replace").splitlines():
            if line.startswith(("native stages:", "native compile:")):
                for k, v in re.findall(r"(\w+)=([0-9.]+)s", line):
                    out[k] = float(v)
    return out


def summarize(receipt):
    rows = []
    for row in receipt["rows"]:
        s = row["sessions"][0]["retained"]
        st = s.get("compiler_stats", {})
        f = flat(st)
        secs = {k: v for k, v in f.items() if "second" in k}
        mem = st.get("memo", {})
        rows.append(dict(
            kind=row["kind"], pre_request_settle_s=row.get("pre_request_settle_s"), retained_wall_s=s["wall_s"],
            fresh_wall_s=(row.get("fresh") or {}).get("wall_s"),
            stage_seconds=secs, native_stages=stage_lines(receipt["root"], row["ordinal"]),
            disk_hits=mem.get("disk_hits"), resident_hits=mem.get("resident_hits"),
            recomputed=mem.get("recomputed"), resident_dropped=mem.get("resident_dropped"),
            bytes_equal=all(h["retained"] == h["fresh"] for h in row.get("output_hashes", {}).values()),
            output_hashes=row.get("output_hashes")))
    cleanup = receipt.get("owned_job_cleanup", {})
    return dict(schema=1, receipt_root=receipt["root"], status=receipt["status"], rows=rows,
                owned_job_memory=cleanup.get("memory"), total_end_to_end_s=receipt.get("total_end_to_end_s"))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--worktree", required=True)
    p.add_argument("--workers", type=int, choices=(2, 8), default=8)
    p.add_argument("--skip-build", action="store_true")
    p.add_argument("--summarize-receipt", help="only summarize an existing receipt.json (no build/run)")
    p.add_argument("--job-memory-mib", type=int, default=12288,
                   help="owned Job commit cap; 6144 killed the 8-worker daemon (allocation failure)")
    p.add_argument("--compiler")
    p.add_argument("--out", default="measure-summary.json")
    a = p.parse_args()
    if a.summarize_receipt:
        summary = summarize(json.loads(Path(a.summarize_receipt).read_text()))
        Path(a.out).write_text(json.dumps(summary, indent=2))
        return 0
    wt = Path(a.worktree)
    exe = a.compiler or (TARGET + "/release/dmbc.exe" if a.skip_build else build(wt))
    cmd = [sys.executable, str(wt / "tools/dmb/bench/native-iteration.py"),
           "--compiler", exe, "--inspector", INSPECTOR, "--byte-oracles-only",
           "--source", f"{BASE}/source",
           "--source-snapshot", f"{BASE}/filtered-admission/source-snapshot.json",
           "--input-closure", f"{BASE}/filtered-admission/input-closure.json",
           "--scenarios", f"{BASE}/filtered-admission/scenarios.json",
           "--byond-pin", f"{BASE}/filtered-admission/byond-structural-pin.json",
           "--byond-dmb", f"{BASE}/recapture/byond/world.dmb",
           "--edits", EDITS, "--workers", str(a.workers), "--total-workers", str(a.workers),
           "--job-memory-mib", str(a.job_memory_mib), "--owned-memory-budget-bytes", str(a.job_memory_mib * 1048576),
           "--sample-owned-memory", "--require-owned-daemon",
           "--overall-seconds", "3600", "--minimum-free-gib", "16",
           "--output-root", "E:/dq-cache/dmb-native-iterations"]
    os.environ.setdefault("DMB_PROBE_BUSY_SECONDS", "180")  # probe waits out daemon pressure release (outside timed region)
    os.environ.setdefault("DMB_SETTLE_QUIET_SECONDS", "45")  # let daemon pressure release finish before each timed request
    started = time.time()
    out = subprocess.run(cmd, cwd=wt, capture_output=True, text=True)
    sys.stderr.write(out.stderr[-3000:])
    print(out.stdout[-2000:])
    line = [l for l in out.stdout.splitlines() if l.strip().startswith("{") and "receipt" in l]
    if not line:
        return out.returncode or 1
    receipt = json.loads(Path(json.loads(line[-1])["receipt"]).read_text())
    summary = summarize(receipt)
    summary["command"] = cmd
    summary["compiler"] = exe
    summary["harness_wall_s"] = time.time() - started
    Path(a.out).write_text(json.dumps(summary, indent=2))
    print(json.dumps({r["kind"]: r["retained_wall_s"] for r in summary["rows"]}))
    return out.returncode


if __name__ == "__main__":
    sys.exit(main())
