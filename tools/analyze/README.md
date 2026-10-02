# analyze: the one lint engine

`tools/analyze` replaces the ~40 Python scripts in `tools/ci/` and `check_grep.sh` (each re-read the
~5,800 `.dm` files serially; ~11 minutes in all) with one Rust binary that loads the tree once, in
parallel, and runs every lint over it. Findings are identical to the legacy scripts (that is what the
parity harness proves); only the cost changes.

```
analyze check [--lint NAME...] [--changed-only] [--no-cache] [--raw] [--ci]
analyze baseline --update|--seed [--lint NAME...]
analyze parity NAME... | --all [--bless] [--fixtures-only]
analyze timing | selftest | list | frontend-diff
```

Build: `cargo build --release --manifest-path tools/analyze/Cargo.toml` (set `RUSTC_WRAPPER=sccache`
when you can). Test: `cargo test --manifest-path tools/analyze/Cargo.toml`.

## Architecture

| Piece | File | What it does |
|---|---|---|
| Tree | `src/tree.rs` | One walk per `(dir, ext)`; lazy text, `(size, mtime)` hash shortcut; `raw()`, `code()` (= `state_schema_lint.code_only`), `clean()` (= `_dx_dm.sanitize`) views, all 1-based line indexed |
| Strippers | `src/strip.rs` | The two comment/string strippers, ported once, bug for bug |
| Regex | `src/pat.rs` | `pat!(r"...")`: Python-`re` semantics; picks `regex` or `fancy-regex` (look-around) per pattern |
| ALLOW | `src/allow.rs` | `// ALLOW(lint[/CODE], ...): reason`, same line or comment line above |
| Baselines | `src/baseline.rs` | Fingerprint baselines (`rule<TAB>file<TAB>normalized line`) and count ceilings, in the exact old file format |
| Scopes | `src/scopes.rs`, `tools/ci/lint_scopes.toml` | Path exemptions, named lists, per-rule ceilings, reason codes |
| Cache | `src/cache.rs` | `data/analyze-cache/`: per-file results keyed `(path, content hash)`, tree memo keyed by the combined hash; stamped with the engine build hash |
| Runner | `src/run.rs` | Parallel run, policy judgement (`Sites` / `Ceilings` / `Hard` / `Custom`), `--changed-only`, baseline rewrite |
| Parity | `src/parity.rs` | Old script vs engine on the real tree and on `fixtures/` |
| Frontend | `src/frontend/` | `Frontend` trait: `TextFrontend` (the line scanner) and `DreamMakerFrontend` (SpacemanDMM `dreammaker`, tag suite-1.11) |
| DM helpers | `src/dm/*.rs` | Shared scanners (`dx.rs` = `_dx_dm.py`, `sys.rs` = the sys_lint family) |
| Lints | `src/lints/*.rs` | One file per lint, found by `build.rs` (no registry to edit) |

## Writing a lint

A lint is a struct implementing `Lint` in `src/lints/<name>.rs` with `pub fn register(reg: &mut Registry)`.
Copy `src/lints/dcs.rs` (a hard-ban lint) or `src/lints/sys_emag.rs` (a sys module).

* `Meta`: `name` (what `--lint` matches; also the ALLOW name when it is the same), `label` (the tag in
  `[label/rule]`), `legacy` (the script it replaces), `select` (which files: `CODE_DM` is
  `code/**/*.dm` like `glob.glob`, which skips dot-files; set `hidden: true` for `os.walk`/`rglob`),
  `scan`, `policy`, `rules` (name + fix hint, in the order the old lint listed them), `allow`
  (ALLOW names it reads), `lists` (keys it reads from its `lint_scopes.toml` section).
* `scan_file(cx, f, out)`: one file. Runs in parallel and is cached per file, so it may depend ONLY
  on that file's content and `f.rel`. `out.site("rule", line)` / `out.site_msg(rule, line, msg)`.
  `out.allowed(f, line, "name")` is the ALLOW question: ask it exactly where the Python called
  `allowed()` (before the pattern, or only for a line that would count; the result is the same but
  the unused-ALLOW check relies on it).
* `scan_tree(cx, out)`: the whole tree (cross-file indexes); memoized on the combined hash of the
  lint's files. `out.site_in("rule", rel, line)`. `cx.files()` = in-scope files minus the lint's
  exemptions (sorted by path); `cx.all_files()` includes exempt ones; `cx.list("key")` reads a named
  list from `lint_scopes.toml`; `cx.tree.get(rel)`, `cx.tree.memo(key, || ...)` for a value several
  lints share (see `DxIndex::get`).
* `policy`: `Sites{baseline, header, banned}` = `check_sites`/`write_sites` (fingerprint ratchet);
  `Ceilings{...}` = `name count` baselines keyed by `Site::key` (`system_boundary`); `Hard` = any site
  fails; `Custom` = override `finish()` / `update_baseline()`.
* `selftest()`: the old `--selftest` fixtures, ported. `parity()`: how `analyze parity` runs the old script.

### Matching the Python exactly

Findings must be identical, so port the *behaviour*, quirks included, and say so in a comment when a
quirk looks like a bug (do not fix it here: fix it in a separate change after parity).

* Text is `open().read()` text: universal newlines, lossy UTF-8. `f.raw()` is that. Lines are
  `text.split("\n")`: a file ending in a newline has a final empty line (`View::num_lines`).
* `f.code()` is `code_only(text)` (NOT length-preserving; an unbalanced `'` swallows text, newlines
  included). `f.clean()` is `sanitize_text` (same byte length, same newlines).
* Python whitespace: use `util::{py_split, py_strip, py_lstrip, py_rstrip, normalize_ws}`, not the
  std ones, where whitespace matters. `util::before_slashes(line)` = `line.split("//", 1)[0]`.
* Regex: `pat!(r"...")`. Python `re.search` = `find`, `re.match` = `pat_match!`, `re.fullmatch` =
  `pat_full!`, `finditer` = `find_iter`. A literal `{` that is not a repetition must be escaped in Rust.
  Python `\Z` is `\z`.
* Per-site order inside a rule matters for baseline matching of duplicates: emit in the Python's order
  (file order is path-sorted here; within a file, line order, then the Python's inner order).
* `Policy::Sites` fingerprints are the *raw file line* normalized, not the message.

### Scopes (`tools/ci/lint_scopes.toml`)

Hard-coded path exemptions and constant lists move out of the lint into the lint's section:

```toml
[lint.scheduler]
exempt_contains = ["/unit_tests/"]
[lint.scheduler.lists]
core_dirs = ["code/datums/om/"]      # read with cx.list("core_dirs"); declare "core_dirs" in Meta::lists
[lint.scheduler.ceilings]            # per-rule count ceilings, judged by count instead of the baseline
spawn = 12
```
`analyze baseline --update` lowers a ceiling, `--seed` sets it. A lint without a section has no exemptions.

## Fixtures and parity

Every lint needs `tools/analyze/fixtures/<lint>/` (a `/` in the name becomes `__`): a small repo-shaped
tree (`code/...`) with positive, negative and edge cases for every rule (comments, strings,
`// ALLOW(x): reason` above and on the line, a `unit_tests/` path, a dot-file if the lint's `Select`
cares, multi-line constructs, the quirks you ported). Then:

```
analyze parity <lint> --fixtures-only --bless   # old script vs engine on the fixtures; writes expected.txt when equal
analyze parity <lint>                           # also: default run, raw sites (baselines ignored), --update/--seed, --selftest on the real tree
```
`cargo test` holds the engine to every `expected.txt` forever, with no Python needed. A lint is
"ported" when `analyze parity <lint>` prints PASS with no `DIFF` line. Parity on the real tree alone proves
nothing for a lint that has no sites there (a hard ban at zero): the fixtures are what prove it.

`Parity` (in the lint's `parity()`): `old` = the old script's CI run; `old_raw` = its `--report` runs
(ignore baselines) or `blank` = baseline files to blank before running it; `parse` = how to read its
output (`Tagged` `file:line: [lbl/rule]`, `Report` `file:line: rule`, `FileLine`, `Bare`); `update`/`seed`/
`files` = byte-for-byte baseline rewrite comparison; `selftest`.

## Tooling gotchas

* Edit Rust with the Write/Edit tools. Shell heredocs and `python -` snippets through the Bash tool have
  been seen to halve backslashes (`'\\'` becomes `'\'`), which silently corrupts regexes.
* Python text-mode writes CRLF on Windows; sources here are LF (`* text=auto`).
* The old scripts take minutes on the real tree (`sys_lint` ~140 s). Use `--fixtures-only` while
  iterating and run the full parity once at the end.
* Never edit `tools/dm-health` (a different project) and do not depend on it.
