#!/usr/bin/env python3
"""Keeps the design docs true (dq-improvements item 1).

Three checks, one script (`python3 tools/ci/check_docs_truth.py`, run by tools/ci/check_ratchets.sh; `--selftest` proves the machinery):

1. The status ledger in doc/rewrite/framework_gaps.md (between the `gaps-ledger` markers). Each line is
       ID :: status :: kind :: pattern :: paths :: evidence
   `status` is open | partial | kept | fixed. `kind` says what the pattern's hits mean:
       gap  the pattern matches while the gap exists (open, partial, kept need a hit; fixed needs none)
       fix  the pattern matches once the fix exists (fixed needs a hit; open, partial need none)
   `pattern` is an extended regex run with `git grep -E` over the space-separated `paths` (one ID may have several lines, all with one status).
   The check fails when a status disagrees with the code, when a table row of the doc names a different status in its first cell than the
   ledger, and when a row marked open or partial has no ledger line (so a new open row must come with a probe).
2. Every `code/...`, `tools/...` and `doc/...` path the gaps doc and AGENTS.md name exists (a path followed by "(deleted)" is history).
3. The generated tables of doc/rewrite/final_api.html section 19 and 20 (between the `census` and `baselines` markers) equal what
   tools/ci/legacy_form_counts.sh and the tools/ci/*baseline*.txt files give now. `--write` regenerates them.
"""
import os
import re
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GAPS = "doc/rewrite/framework_gaps.md"
API = "doc/rewrite/final_api.html"
PATH_DOCS = [GAPS, "AGENTS.md"]
STATUSES = ("open", "partial", "kept", "fixed")
KINDS = ("gap", "fix")
LEDGER_BEGIN = "<!-- gaps-ledger:begin -->"
LEDGER_END = "<!-- gaps-ledger:end -->"


def read(root, rel):
    with open(os.path.join(root, rel), encoding="utf8") as f:
        return f.read()


def grep_hits(root, pattern, paths):
    """Number of matching lines of `pattern` under `paths` (git grep --no-index: works in a plain directory too)."""
    cmd = ["git", "grep", "--no-index", "-I", "-c", "-E", "-e", pattern, "--"] + paths
    r = subprocess.run(cmd, cwd=root, capture_output=True, text=True, encoding="utf8", errors="replace")
    if r.returncode not in (0, 1):
        raise RuntimeError("git grep failed for %r: %s" % (pattern, r.stderr.strip()))
    total = 0
    for line in r.stdout.splitlines():
        if ":" in line:
            total += int(line.rsplit(":", 1)[1])
    return total


def parse_ledger(text):
    if LEDGER_BEGIN not in text or LEDGER_END not in text:
        return None, ["ledger markers %s ... %s not found in %s" % (LEDGER_BEGIN, LEDGER_END, GAPS)]
    body = text.split(LEDGER_BEGIN, 1)[1].split(LEDGER_END, 1)[0]
    rows, errors = [], []
    for n, line in enumerate(body.splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("```") or line.startswith("#"):
            continue
        parts = [p.strip() for p in line.split(" :: ")]
        if len(parts) != 6:
            errors.append("ledger line %d: want 'ID :: status :: kind :: pattern :: paths :: evidence', got %d fields: %s" % (n, len(parts), line[:80]))
            continue
        rid, status, kind, pattern, paths, evidence = parts
        if status not in STATUSES:
            errors.append("ledger %s: status %r is not one of %s" % (rid, status, "/".join(STATUSES)))
        if kind not in KINDS:
            errors.append("ledger %s: kind %r is not gap or fix" % (rid, kind))
        if not paths.split():
            errors.append("ledger %s: no paths" % rid)
        if len(evidence) < 10:
            errors.append("ledger %s: the evidence is missing" % rid)
        rows.append({"id": rid, "status": status, "kind": kind, "pattern": pattern, "paths": paths.split(), "evidence": evidence})
    return rows, errors


ROW_ID = re.compile(r"^\|\s*([A-Z][A-Za-z0-9]*-?[A-Za-z0-9]*\d+[a-z]?(?:-codex\d+)?)\b")


def doc_row_status(first_cell):
    """The status a table row's first cell states, or None when it states none."""
    if re.search(r"PARTLY|PARTIAL", first_cell):
        return "partial"
    if re.search(r"\bDONE\b|\bDOCUMENTED\b|\bAUDITED\b|\bfixed\b", first_cell):
        return "fixed"
    if re.search(r"\bopen\b|\bOPEN\b", first_cell, re.I):
        return "open"
    if re.search(r"\bkept\b|\bKEPT\b", first_cell):
        return "kept"
    return None


def doc_rows(text):
    """id -> list of (line number, stated status) for the table rows of the gaps doc."""
    out = {}
    for n, line in enumerate(text.splitlines(), 1):
        m = ROW_ID.match(line)
        if not m:
            continue
        first = line.split("|")[1] if line.count("|") > 1 else ""
        out.setdefault(m.group(1), []).append((n, doc_row_status(first)))
    return out


def check_ledger(root):
    errors = []
    text = read(root, GAPS)
    rows, errs = parse_ledger(text)
    errors += errs
    if rows is None:
        return errors
    status_of = {}
    for r in rows:
        if status_of.setdefault(r["id"], r["status"]) != r["status"]:
            errors.append("ledger %s: lines disagree on the status" % r["id"])
        try:
            hits = grep_hits(root, r["pattern"], r["paths"])
        except RuntimeError as e:
            errors.append("ledger %s: %s" % (r["id"], e))
            continue
        gap_present = (hits > 0) if r["kind"] == "gap" else (hits == 0)
        # gap kind: a hit is the gap. fix kind: no hit is the gap.
        want_gap = r["status"] != "fixed"
        if gap_present != want_gap:
            errors.append("ledger %s says %s but the %s probe /%s/ over %s has %d hit(s): %s" % (
                r["id"], r["status"], r["kind"], r["pattern"], " ".join(r["paths"]), hits,
                "the gap is gone, mark it fixed" if want_gap else "the gap is back, or the row was marked fixed too early"))
    table = doc_rows(text)
    for rid, status in status_of.items():
        found = table.get(rid)
        if not found:
            continue
        for n, stated in found:
            if stated is None:
                errors.append("%s:%d row %s states no status in its first cell; the ledger says %s" % (GAPS, n, rid, status))
            elif stated != status:
                errors.append("%s:%d row %s states %s in its first cell; the ledger says %s" % (GAPS, n, rid, stated, status))
    for rid, found in table.items():
        for n, stated in found:
            if stated in ("open", "partial") and rid not in status_of:
                errors.append("%s:%d row %s is %s and has no probe: add a line to the gaps ledger" % (GAPS, n, rid, stated))
    return errors


# Build output and gitignored directories: named in the docs, absent from a fresh checkout.
GENERATED_PATHS = ("code/_generated", "code/engine/_generated", "code/__defines/verdigris", "icons/gen", "verdigris/target", "tgui/packages/tgui/interfaces/generated")

# What may follow a path that is history: "(deleted)", "(deleted; now x)", ", deleted)", "are deleted", "is gone".
HISTORY_RE = re.compile(r"^[`\s:\d,-]*(\(deleted|\(gone|deleted\)|(?:are|is|was|were) (?:deleted|gone))")

PATH_RE = re.compile(r"(?<![\w/.\-])((?:code|tools|doc|maps|icons|interface|tgui|verdigris|SQL|config|html|strings|sound)/[\w./\-]*[\w/])")


def check_paths(root):
    errors = []
    for rel in PATH_DOCS:
        text = read(root, rel)
        for n, line in enumerate(text.splitlines(), 1):
            if LEDGER_BEGIN in line:
                continue
            for m in PATH_RE.finditer(line):
                p = re.sub(r":\d+(?:[,-]\d+)*$", "", m.group(1)).rstrip(".")
                if any(c in p for c in "*<>{}[]") or p.endswith("/..."):
                    continue
                if HISTORY_RE.match(line[m.end():m.end() + 40]):
                    continue
                if any(p == g or p.startswith(g + "/") for g in GENERATED_PATHS):
                    continue
                if p.endswith(".dmi") and os.path.exists(os.path.join(root, p + ".toml")):
                    continue  # icons are built from png + dmi.toml
                if not os.path.exists(os.path.join(root, p)):
                    errors.append("%s:%d names %s, which does not exist (fix the path, or follow it with '(deleted)' when it is history)" % (rel, n, p))
    return errors


# ---- generated tables of final_api.html -----------------------------------------------------------------------------------------------

CENSUS_BEGIN, CENSUS_END = "<!-- census:begin -->", "<!-- census:end -->"
BASE_BEGIN, BASE_END = "<!-- baselines:begin -->", "<!-- baselines:end -->"


def census_lines(root):
    override = os.environ.get("DQ_CENSUS_FILE")
    if override:
        with open(override, encoding="utf8") as f:
            return f.read().splitlines()
    r = subprocess.run(["bash", "tools/ci/legacy_form_counts.sh"], cwd=root, capture_output=True, text=True, encoding="utf8")
    if r.returncode != 0:
        raise RuntimeError("legacy_form_counts.sh failed: " + r.stderr.strip())
    return r.stdout.splitlines()


def gen_census(root):
    rows = []
    for line in census_lines(root):
        parts = line.split("\t")
        if len(parts) == 3:
            rows.append((parts[0], parts[1], parts[2]))
    live = [r for r in rows if r[1] not in ("0", "-")]
    out = ['  <div class="prose"><p>Census of <code>tools/ci/legacy_form_counts.sh</code>: %d forms counted, %d with a call site left. A form that counts 0 is a hard ban in <code>[lint.legacy_forms.lists]</code> (or its own lint). This table is generated by <code>tools/ci/check_docs_truth.py --write</code> and checked by <code>tools/ci/check_ratchets.sh</code>.</p></div>' % (len(rows), len(live))]
    out.append('  <div class="tbl"><table>')
    out.append('    <thead><tr><th>Form</th><th class="n">Sites</th><th class="n">Files</th></tr></thead>')
    out.append("    <tbody>")
    for form, sites, files in rows:
        out.append('      <tr><td><code>%s</code></td><td class="n">%s</td><td class="n">%s</td></tr>' % (form, sites, files))
    out.append("    </tbody>")
    out.append("  </table></div>")
    return out


def baseline_files(root):
    ci = os.path.join(root, "tools", "ci")
    found = []
    for base in (ci, os.path.join(ci, "sys_baseline")):
        if os.path.isdir(base):
            for name in sorted(os.listdir(base)):
                if name.endswith(".txt") and (base != ci or name.endswith("_baseline.txt")):
                    found.append(os.path.join(base, name))
    return found


def gen_baselines(root):
    sizes = []
    for path in baseline_files(root):
        with open(path, encoding="utf8", errors="replace") as f:
            n = sum(1 for line in f if line.strip() and not line.lstrip().startswith("#"))
        sizes.append((os.path.relpath(path, os.path.join(root, "tools", "ci")).replace(os.sep, "/"), n))
    live = [s for s in sizes if s[1] > 0]
    total = sum(n for _, n in sizes)
    out = ['  <div class="prose"><p>%d baseline files under <code>tools/ci/</code> (<code>*_baseline.txt</code> and <code>sys_baseline/*.txt</code>), %d non-empty, %d fingerprint lines in all. A baseline is deleted in the commit that makes its lint a hard ban. This paragraph is generated by <code>tools/ci/check_docs_truth.py --write</code>.</p></div>' % (len(sizes), len(live), total)]
    if live:
        out.append('  <div class="tbl"><table>')
        out.append('    <thead><tr><th>Baseline</th><th class="n">Lines</th></tr></thead>')
        out.append("    <tbody>")
        for name, n in sorted(live, key=lambda s: -s[1]):
            out.append('      <tr><td><code>%s</code></td><td class="n">%d</td></tr>' % (name, n))
        out.append("    </tbody>")
        out.append("  </table></div>")
    return out


def splice(text, begin, end, lines):
    if begin not in text or end not in text:
        return None
    head, rest = text.split(begin, 1)
    _, tail = rest.split(end, 1)
    return head + begin + "\n" + "\n".join(lines) + "\n  " + end + tail


def check_generated(root, write=False):
    errors = []
    text = read(root, API)
    new = text
    for begin, end, gen in ((CENSUS_BEGIN, CENSUS_END, gen_census), (BASE_BEGIN, BASE_END, gen_baselines)):
        spliced = splice(new, begin, end, gen(root))
        if spliced is None:
            errors.append("%s: markers %s ... %s not found" % (API, begin, end))
            continue
        new = spliced
    if new != text:
        if write:
            with open(os.path.join(root, API), "w", encoding="utf8", newline="") as f:
                f.write(new)
            print("check_docs_truth: rewrote the generated tables of %s" % API)
        else:
            errors.append("%s: the generated census/baseline tables are stale; run `python3 tools/ci/check_docs_truth.py --write`" % API)
    return errors


def run(root, write=False):
    errors = []
    errors += check_ledger(root)
    errors += check_paths(root)
    errors += check_generated(root, write)
    return errors


# ---- self-test --------------------------------------------------------------------------------------------------------------------------

def selftest():
    import shutil
    import tempfile

    tmp = tempfile.mkdtemp(prefix="docs_truth_")
    failures = []
    try:
        def put(rel, text):
            p = os.path.join(tmp, rel)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "w", encoding="utf8", newline="") as f:
                f.write(text)

        census = os.path.join(tmp, "census.tsv")
        put("census.tsv", "om_after\t0\t0\nPUBLISH_LEGACY\t3\t2\n")
        os.environ["DQ_CENSUS_FILE"] = census
        put("code/a.dm", "/proc/new_form()\n\tgap_marker()\n")
        put("tools/ci/x_baseline.txt", "# header\nrow one\n")
        put("AGENTS.md", "See `code/a.dm` and `code/gone.dm` (deleted).\n")
        html = "<p>\n" + CENSUS_BEGIN + "\nold\n  " + CENSUS_END + "\n" + BASE_BEGIN + "\nold\n  " + BASE_END + "\n"
        put(API, html)

        def gaps(ledger, rows):
            put(GAPS, rows + "\n" + LEDGER_BEGIN + "\n```text\n" + ledger + "\n```\n" + LEDGER_END + "\n")

        def expect(name, ledger, rows, want):
            gaps(ledger, rows)
            errs = check_ledger(tmp)
            joined = " | ".join(errs)
            if want is None and errs:
                failures.append("%s: wanted clean, got %s" % (name, joined))
            elif want is not None and not any(want in e for e in errs):
                failures.append("%s: wanted an error containing %r, got %s" % (name, want, joined or "none"))

        row_open = "| X1 (open) | where | what |\n"
        row_done = "| X1 **DONE** | where | what |\n"
        good_open = "X1 :: open :: gap :: gap_marker :: code :: the marker is still in code/a.dm today"
        expect("open row with a live gap passes", good_open, row_open, None)
        expect("open but the gap is gone", "X1 :: open :: gap :: nothing_like_this :: code :: the marker was removed from the code", row_open, "the gap is gone")
        expect("fixed but the gap is back", "X1 :: fixed :: gap :: gap_marker :: code :: the marker should be gone by now", row_done, "the gap is back")
        expect("fixed with a fix probe passes", "X1 :: fixed :: fix :: new_form :: code :: new_form exists in code/a.dm", row_done, None)
        expect("open with a fix probe that hits", "X1 :: open :: fix :: new_form :: code :: new_form exists in code/a.dm", row_open, "the gap is gone")
        expect("row text disagrees with the ledger", good_open, row_done, "states fixed")
        expect("open row without a probe", good_open, row_open + "| X2 (open) | where | what |\n", "has no probe")
        expect("partial row without a probe", good_open, row_open + "| X3 (PARTIAL, lane) | where | what |\n", "has no probe")
        expect("bad status", "X1 :: stale :: gap :: gap_marker :: code :: the marker is still in code/a.dm", row_open, "status")
        expect("short line", "X1 :: open", row_open, "want 'ID")

        gaps(good_open, row_open)
        if check_paths(tmp):
            failures.append("paths: a '(deleted)' path and an existing path must pass, got %s" % check_paths(tmp))
        put("AGENTS.md", "See `code/gone.dm`.\n")
        if not any("code/gone.dm" in e for e in check_paths(tmp)):
            failures.append("paths: a missing path must fail")
        put("AGENTS.md", "ok\n")

        if not check_generated(tmp):
            failures.append("generated: stale tables must fail")
        if check_generated(tmp, write=True):
            failures.append("generated: --write must not report errors")
        if check_generated(tmp):
            failures.append("generated: after --write the tables must match, got %s" % check_generated(tmp))
        written = read(tmp, API)
        if "PUBLISH_LEGACY" not in written or "1 baseline files under" not in written:
            failures.append("generated: the census row and the baseline count must be written")
        put("tools/ci/x_baseline.txt", "# header\nrow one\nrow two\n")
        if not check_generated(tmp):
            failures.append("generated: a changed baseline must make the tables stale")
    finally:
        os.environ.pop("DQ_CENSUS_FILE", None)
        shutil.rmtree(tmp, ignore_errors=True)
    for f in failures:
        print("check_docs_truth selftest FAILED: " + f)
    if failures:
        return 1
    print("check_docs_truth selftest: ok")
    return 0


def main(argv):
    if "--selftest" in argv:
        return selftest()
    errors = run(ROOT, write="--write" in argv)
    for e in errors:
        print("check_docs_truth: " + e)
    if errors:
        print("check_docs_truth: %d problem(s). Docs must match the code: fix the row, the ledger line or the code." % len(errors))
        return 1
    print("check_docs_truth: gaps ledger, doc paths and generated tables are true.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
