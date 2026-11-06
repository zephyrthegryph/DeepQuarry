#!/usr/bin/env python3
"""Keeps the design docs true (dq-improvements item 1).

Four checks, one script (`python3 tools/ci/check_docs_truth.py`, run by tools/ci/check_ratchets.sh; `--selftest` proves the machinery):

1. The status ledger in doc/rewrite/framework_gaps.md (between the `gaps-ledger` markers). Each line is
       ID :: status :: kind :: pattern :: paths :: evidence
   `status` is open | partial | kept | fixed. `kind` says what the pattern's hits mean:
       gap  the pattern matches while the gap exists (open, partial, kept need a hit; fixed needs none)
       fix  the pattern matches once the fix exists (fixed needs a hit; open, partial need none)
   `pattern` is an extended regex run with `git grep -E` over the space-separated `paths` (one ID may have several lines, all with one status).
   The check fails when a status disagrees with the code, when a table row of the doc names a different status in its first cell than the
   ledger, and when a row marked open or partial has no ledger line (so a new open row must come with a probe).
2. Every `code/...`, `tools/...` and `doc/...` path the gaps doc, AGENTS.md, the API reference, doc/rewrite/README.md and doc/testing.md name exists (a path followed by "(deleted)" is history).
4. doc/rewrite/api_reference.md, the catalogue of what to use: every `Defined:` line cites a `path:line` whose file holds the entry's
   form name within a few lines (so a renamed or moved form fails here), every other `path:line` citation (an `Example:` call site
   must show its call within a few lines) is inside its file, every name in the section 17 `Banned` table is still a banned name in
   tools/ci/lint_scopes.toml, and every section 19 Landing entry's `Probe:` regex still finds nothing in the code (when it does, the
   form has landed and the entry moves into the body). Adding or changing a form means updating that file in the same commit.
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
PATH_DOCS = [GAPS, "AGENTS.md", "doc/rewrite/api_reference.md", "doc/rewrite/README.md", "doc/testing.md"]
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
GENERATED_PATHS = ("code/_generated", "code/engine/_generated", "code/__defines/verdigris", "icons/gen", "verdigris/target", "tools/dmb/target", "tgui/packages/tgui/interfaces/generated")

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
    errors += check_api_reference(root)
    return errors


# ---- the API reference ----------------------------------------------------------------------------------------------------------------

API_REF = "doc/rewrite/api_reference.md"
TOML = "tools/ci/lint_scopes.toml"
BANNED_HEADING = "## 17."
LANDING_HEADING = "## 19."

TICK = re.compile(r"`([^`\n]+)`")
REF_SPAN = re.compile(r"^([\w./\-]+\.\w+):(\d+)(?:[-,]\d+)*$")
CITE = re.compile(r"(?<![\w/.\-])((?:code|tools|doc|verdigris|tgui|html|maps|interface|SQL|config)/[\w./\-]*\.\w+):(\d+)")
API_MIN_ENTRIES = 20  # fewer entries than this means the body of the reference was lost
EXAMPLE_WINDOW = (4, 4)  # an Example: call site must show its call within this many lines of the cited line
NAME_WINDOW = (6, 40)  # a Defined: name must appear this many lines before and after the cited line


def entry_name(span):
    """The form a heading span names: `foo(a, b)` is foo, `/datum/gas_mixture` is gas_mixture, `req_*` is req_."""
    span = span.strip()
    m = re.match(r"^((?:/[\w]+)+)", span)
    if m:
        return m.group(1).rsplit("/", 1)[1]
    m = re.match(r"^[A-Za-z_][\w]*", span)
    return m.group(0) if m else None


def example_probe(line, cite_start):
    """The identifier an Example: citation should show: the first call (or, failing that, word of 4+ characters) of the code span just before the citation."""
    prev = None
    for m in TICK.finditer(line[:cite_start]):
        if not REF_SPAN.match(m.group(1)):
            prev = m
    if prev is None:
        return None
    code = prev.group(1)
    m = re.search(r"([A-Za-z_][\w]{3,})\(", code) or re.search(r"([A-Za-z_][\w]{3,})", code)
    return m.group(1) if m else None


def lines_of(root, rel):
    try:
        return read(root, rel).splitlines()
    except (OSError, UnicodeDecodeError):
        return None


def check_cite(root, rel, doc_line, path, ln, name=None, window=None):
    """Errors for one path:line citation: the file exists, the line is inside it, and `name` (when given) is within the window of it."""
    if any(path == g or path.startswith(g + "/") for g in GENERATED_PATHS):
        return []
    lines = lines_of(root, path)
    if lines is None:
        return ["%s:%d cites %s:%d, which does not exist" % (rel, doc_line, path, ln)]
    if ln < 1 or ln > len(lines):
        return ["%s:%d cites %s:%d, but the file has %d lines" % (rel, doc_line, path, ln, len(lines))]
    if name:
        w = window or NAME_WINDOW
        lo, hi = max(1, ln - w[0]), min(len(lines), ln + w[1])
        pat = re.compile(r"(?<![\w])" + re.escape(name) + r"(?![\w])")
        if not any(pat.search(l) for l in lines[lo - 1:hi]):
            return ["%s:%d says %s is defined at %s:%d, but %s is not within lines %d-%d of it (the form moved or was renamed: update the citation)" % (rel, doc_line, name, path, ln, name, lo, hi)]
    return []


def parse_defined(line):
    """[(label or None, path, line)] for the path:line spans of a `Defined:` line. A label is a backticked name just before the ref (`name` at `path:line`)."""
    out, prev = [], None
    spans = list(TICK.finditer(line))
    for i, m in enumerate(spans):
        text = m.group(1)
        r = REF_SPAN.match(text)
        if r:
            label = None
            if prev is not None and re.match(r"^\s*(at|in|:|is at)?\s*$", line[prev.end():m.start()]):
                label = entry_name(prev.group(1))
            out.append((label, r.group(1), int(r.group(2))))
        prev = m
    return out


def check_banned_table(root, lines):
    errors = []
    try:
        toml = read(root, TOML).splitlines()
    except OSError:
        return ["%s is missing" % TOML]
    start = next((i for i, l in enumerate(lines) if l.startswith(BANNED_HEADING)), None)
    if start is None:
        return ["%s has no '%s' section (the banned-forms tables)" % (API_REF, BANNED_HEADING)]
    in_table = False
    for n in range(start + 1, len(lines)):
        line = lines[n]
        if line.startswith("## "):
            break
        if re.match(r"^\|\s*Banned\s*\|", line):
            in_table = True
            continue
        if not in_table or not line.startswith("|") or re.match(r"^\|[\s\-|]+\|?$", line):
            if not line.startswith("|"):
                in_table = False
            continue
        first = line.split("|")[1]
        for m in TICK.finditer(first):
            raw = m.group(1).strip().rstrip("*(").rstrip("()")
            if not raw:
                continue
            pat = re.compile(r'^\s*"\s*' + re.escape(raw) + r"""(?:[\s*(=@"]|$)""")
            if not any(pat.match(t) for t in toml):
                errors.append("%s:%d banned name %s is not a banned name in %s any more (it was un-banned or renamed: fix the table)" % (API_REF, n + 1, raw, TOML))
    return errors


def check_landing(root, lines):
    errors = []
    start = next((i for i, l in enumerate(lines) if l.startswith(LANDING_HEADING)), None)
    if start is None:
        return ["%s has no '%s' section (the landing entries)" % (API_REF, LANDING_HEADING)]
    head, line_no, probed = None, 0, False
    entries = []
    for n in range(start + 1, len(lines)):
        line = lines[n]
        if line.startswith("## "):
            break
        if line.startswith("#### "):
            entries.append([line[5:].strip(), n + 1, None])
        m = re.match(r"^Probe:\s*`([^`]+)`(?:\s+in\s+`([^`]+)`)?", line)
        if m and entries:
            entries[-1][2] = (m.group(1), (m.group(2) or "code").split())
    for title, n, probe in entries:
        if probe is None:
            errors.append("%s:%d landing entry '%s' has no Probe: line (a regex that finds nothing until the form lands)" % (API_REF, n, title[:50]))
            continue
        try:
            hits = grep_hits(root, probe[0], probe[1])
        except RuntimeError as e:
            errors.append("%s:%d landing probe: %s" % (API_REF, n, e))
            continue
        if hits:
            errors.append("%s:%d landing entry '%s' has landed: its probe /%s/ now finds %d line(s) in %s. Move the entry into the body with a Defined: line" % (API_REF, n, title[:50], probe[0], hits, " ".join(probe[1])))
    return errors


def check_api_reference(root):
    """Every Defined: citation points at a file and line holding the form's name; every other path:line citation is inside its file;
    the Banned tables name banned forms; every Landing entry's probe still finds nothing."""
    errors = []
    try:
        text = read(root, API_REF)
    except OSError:
        return ["%s is missing" % API_REF]
    lines = text.splitlines()
    in_landing = False
    heading_name, entries_seen = None, 0
    fenced = False
    for n, line in enumerate(lines, 1):
        if line.startswith("```"):
            fenced = not fenced
            continue
        if fenced:
            continue
        if line.startswith("## "):
            in_landing = line.startswith(LANDING_HEADING)
        if line.startswith("#### "):
            m = TICK.search(line)
            heading_name = entry_name(m.group(1)) if m else None
            if not in_landing:
                entries_seen += 1
            continue
        if line.startswith("Defined:") and not in_landing:
            refs = parse_defined(line)
            if not refs:
                errors.append("%s:%d Defined: line has no `path:line` citation" % (API_REF, n))
            for i, (label, path, ln) in enumerate(refs):
                errors += check_cite(root, API_REF, n, path, ln, label or (heading_name if i == 0 else None))
            continue
        for m in CITE.finditer(line):
            probe = example_probe(line, m.start()) if line.startswith("Example:") else None
            errors += check_cite(root, API_REF, n, m.group(1), int(m.group(2)), probe, EXAMPLE_WINDOW)
    if entries_seen < API_MIN_ENTRIES:
        errors.append("%s has only %d entries; the reference lost its body" % (API_REF, entries_seen))
    errors += check_banned_table(root, lines)
    errors += check_landing(root, lines)
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
        for extra in PATH_DOCS:
            if extra not in (GAPS, "AGENTS.md"):
                put(extra, "ok\n")

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

        # the API reference: citations, the banned table and the landing probes
        global API_MIN_ENTRIES
        API_MIN_ENTRIES = 1
        put("code/b.dm", "x\n/proc/alpha_form()\n\tbody\n" + "filler\n" * 80)
        put("tools/ci/lint_scopes.toml", '[lint.legacy_forms.lists]\nbanned = [\n  "old_form = use alpha_form",\n]\n')

        def api(defined="`code/b.dm:2`", example="`alpha_form(1)`, `code/b.dm:2`", banned="old_form", probe="`beta_form\\(`"):
            put(API_REF, "## 3. Forms\n#### `alpha_form(x)`\nDefined: %s\nExample: %s\n## 17. Banned\n| Banned | Use |\n|---|---|\n| `%s` | `alpha_form()` |\n## 19. Landing\n#### `beta_form()`\n%s\n" % (defined, example, banned, ("Probe: " + probe) if probe else "Landing only."))

        def api_expect(name, want, **kw):
            api(**kw)
            errs = check_api_reference(tmp)
            joined = " | ".join(errs)
            if want is None and errs:
                failures.append("api %s: wanted clean, got %s" % (name, joined))
            elif want is not None and not any(want in e for e in errs):
                failures.append("api %s: wanted an error containing %r, got %s" % (name, want, joined or "none"))

        api_expect("a true reference passes", None)
        api_expect("a renamed form fails", "is not within lines", defined="`code/b.dm:60`")
        api_expect("a citation past the end fails", "has 83 lines", defined="`code/b.dm:200`")
        api_expect("a missing file fails", "does not exist", defined="`code/gone.dm:2`")
        api_expect("a label names the form of its own ref", None, defined="`code/b.dm:2`, `alpha_form` at `code/b.dm:2`")
        api_expect("an example must show its call", "is not within lines", example="`alpha_form(1)`, `code/b.dm:70`")
        api_expect("a name no longer banned fails", "not a banned name", banned="young_form")
        api_expect("a landing entry without a probe fails", "no Probe", probe=None)
        put("code/c.dm", "beta_form(1)\n")
        api_expect("a landed form fails its probe", "has landed")
        os.remove(os.path.join(tmp, "code/c.dm"))
        api_expect("a landing probe that finds nothing passes", None)
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
