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
| Semantic layer | `src/sem/`, `src/gens/` | Type/proc/var resolution on dreammaker, generated reads, key resolution, handler checks, generators (see "Semantic layer") |

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
output (`Tagged` `file:line: [lbl/rule]`, `Bracketed` `file:line: [rule]`, `Report` `file:line: rule`,
`FileLine`, `Bare`); `update`/`seed`/
`files` = byte-for-byte baseline rewrite comparison; `selftest`.

### The `check_grep` lint (a shell script's worth of `rg`/`grep`)

`src/lints/check_grep/` ports `tools/ci/check_grep.sh`. A check is a `Part` (`framework.rs`): the search
(`line`, `line_g` = GNU `grep -P` with ASCII classes, `multi_u` = `rg -PU`, `multi_z` = `grep -Pzo`, a
file test) plus the `grep -v` stages after it as filters over the composite `rel:line:text` the script
printed (so a path allowlist, a `:\s*//` comment test and a `var/` substring behave as in the shell).
`parts_*.rs` list them, one rule per part (rule = slug of the script's `part "..."` title, `__what` for a
second check under one title). Path allowlists are `[lint.check_grep.lists]`, the count ratchets are
`[lint.check_grep.ceilings]`, the colour-macro limit is `MACRO_COUNT` in `dependencies.sh`. To add a check,
add a `Part` and (if it has a path allowlist) its list; `cargo test` holds the rule names to the titles.

Engine hooks it needed (both default to doing nothing): `Lint::extra_inputs` (files outside `select` that
`scan_tree` reads: `*.dme`, the example config, `html/changelogs/example.yml`; their hashes key the tree
memo) and `Lint::parity_normalize` (rewrites raw findings into what the script prints: counts instead of
sites, the `a || b || c` first-hit rule). `ParseKind::CheckGrep` reads the script's coloured `NN- title`
output; a legacy `.sh` runs under bash from the repo root as a copy without `errexit` (it aborts at its
first hit otherwise), with `LC_ALL=C.UTF-8`; set `DQ_BASH` to the bash to use (on Windows the first
`bash` `Command` finds can be the WSL launcher).

Running the old script on Windows needs `rg` with PCRE2 on `PATH` and a shim for the file-argument limit
(`rg.exe` and msys `grep` cannot take ~5,900 paths): wrap both to run in chunks of 100 paths with `-H`.

## Semantic layer (E5)

`src/sem/` is the semantic layer of the engine (doc/rewrite/final_api.html section 19, E5): type, proc and var
resolution on the dreammaker backend, generated reads, key resolution, the handler checks, and the generator API
the other engines write their generators against. Three lints (`sem/reads`, `sem/keys`, `sem/handlers`), two
generators (`reads`, `system_accessors`), one oracle (the reads spike).

```
analyze sem reads /obj/machinery/power/apc cell_low     what a handler reads (key, kind, declaring type, diagnostics)
analyze sem oracle [--all]                              the reads spike: generated reads vs the hand-written lists
analyze gen [--check] [NAME...]                         write (or check) code/engine/_generated/*.dm
analyze fixture sem/keys [--bless]                      findings with messages on fixtures/sem__keys; --bless writes expected.txt
```

(On Windows Git Bash set `MSYS_NO_PATHCONV=1` when an argument is a type path.)

### Backend and cost

`Sem` (`src/sem/mod.rs`) owns the dreammaker `ObjectTree` parsed with proc bodies: the real tree parses in 7-8 s, so
nothing parses until a rule needs it, and rules ask for the cheapest model that answers:

| Model | Built by | Cost | Used for |
|---|---|---|---|
| none (text) | `Decls::get` (per file, parallel, memoized) | ~0.17 s | markers, ids, keys, relations, tracked vars, `#define` names |
| partial | `Sem::build_partial(files)`: the named files plus `code/__defines/**` | ~0.15 s for 10 files | per-proc checks (ACT_TRY pairing, context escape) on the files that mention an action or a context |
| full | `Sem::build` / `Cx::sem()` (memoized per run) | 7-8 s | reads, signatures, context fields, purity, the oracle; built only when a declaration names a handler |

A tree whose declarations name no handler (the tree today, before content converts) pays a scan, never a parse:
`handlers::analyzed()` returns `None` before building the model. The incremental compiler's analysis API replaces
dreammaker by implementing `Sem`'s small surface (`ty`, `var_decl`, `proc_ref`, `proc_body`, `owner_candidates`,
`def_at`); no rule names a dreammaker type outside `src/sem/`.

### Declarations the analysis reads

Markers expand to nothing in DM (`code/__defines/engine/markers.dm`), so they are read from comment-stripped text with
balanced parentheses (a marker may span lines; a marker in a comment is documentation, not a declaration):

| Marker | What the engine takes from it |
|---|---|
| `STAT(T, name, RULE, ...)` | stat `STAT_<NAME>` on `T`; `name` is a stat var (a plain read) |
| `SOURCE_DEF(name)` / `STAGE_DEF(group, name)` | `SRC_<NAME>` / `STAGE_<GROUP>_<NAME>` |
| `CAPABILITY_DEF(name, CAP_X, ...)` / `CAPABILITY_TYPE(name, CAP_X, /type, ...)` | capability key `name`, id `CAP_X`; every `op("x", ...)` inside is op key `name.x` |
| `cap_keys(CAP_X, OPEN = ..., ...)` | state ids `<NAME>_OPEN` for the capability whose id is `CAP_X` |
| `CAPABILITIES(T, entries...)` | the holder type `T` of the handlers named inside; `op("x")` is op key `x` |
| `SYSTEM_ACCESSOR(system, name, nameof(var))` | the accessor proc `name()`; a call is a read of `var` on the system (`ReadKind::System`) |
| `READS_AS(proc, KEY, via = nameof(relation))` | `proc` stands for producer key `KEY`; it is not followed. Its owner is the type whose definition sits next to the marker (or `/type/proc/name`) |
| `READS_FROM(C, D)` | first line of a global helper: it is followed through the named args; `READS_FROM()` reads nothing |

Relations are `REL/OWN/REL_LIST/...(/type, var)` or `rel_one/rel_many(nameof(var))` in a `relations()` body; tracked vars are
`TRACKED/SETTER/OM_FIELD...` (or a `__setter_<var>` proc); constants are vars nothing writes outside a constructor.

Handlers are the `PROC_REF(x)` / `TYPE_PROC_REF(/t, x)` / `CAP_PROC(x)` named inside a hook form of a marker. The hook form
decides the context type the handler is called with and its role (`sem/hooks.rs`):

| Hook form | Context | Role |
|---|---|---|
| `needs`, `req` | `/datum/act/op` | requirement (pure, boolean) |
| `when`, `when =`, `look_layer` | `/datum/act/eval` | condition (pure, boolean) |
| `contributes`, `outputs` | `/datum/act/eval` | contribution / output (pure) |
| `then` | `/datum/act/op` | effect (may write) |
| `because =` | `/datum/act/op` | reason (pure) |
| `every`, `after`, `delayed` | `/datum/act/timer` | work |
| `on_notice`, `on_op`, `on_change` | `/datum/act/notice` | reaction |
| `asks`, `request` | `/datum/act/request` | request callback |

### Generated reads

`ReadsEngine::analyze_handler(type, proc, ctx_type)` walks the proc body and returns a `ReadSet` (`src/sem/reads.rs`):
every read as `(root, hops, var, owning type, kind)`, context fields read through `A`, diagnostics, and the effects
(writes and observable calls) the walk saw. What it resolves, per the graph contract: the holder's vars; hops through declared
relations (list relations read `name[]`); procs of the same type and of a hop's type, and `..()`; global helpers through
`READS_FROM`; `READS_AS` accessors (not followed); `native("x")`; system accessors; `A.actor/held/target` as typed hops (root
`actor`, ...). A static over-approximation: every read in the body counts, whichever branch it sits in. Not followed, by
design: engine-internal dirs (`handlers::OPAQUE_DIRS`: dispatchers that read `vars[]`), a subtype's override of a proc, anything
behind a hop that is not a declared relation (the read of the far var is kept, flagged `hop_ok = false`).

Diagnostics (rules of `sem/reads`): `unknown_read` (a var that is not tracked, a relation, a stat, derived or constant),
`unannotated_global`, `dynamic_read` (`vars[]`, `call()`), `hop_not_relation`, `unknown_field`, `condition_cycle` (same-entity
edges between `derive_<var>()` values; a cycle through a relation hop is a runtime topology, the kernel refuses it when the
edge is added), `reads_as_uncovered` (a `READS_AS` accessor reading untracked state that nothing publishes under its key).
Ranks (`sem/graph.rs`): 0 for a value that reads only base state, else one more than its deepest derived read; a handler's
rank in `reads.dm` is one more than the deepest derived value it reads.

**The spike (oracle).** `tools/analyze/oracle/spike.toml` pins 20 real handlers; `cargo test --test oracle` and `analyze sem
oracle` check that the generated reads contain every read in their hand-written lists (`derived()` entries and the lists
the legacy lint generated into `code/_generated/reads.dm`). Result: 20 of 20 contain every hand-written read and none needs a
`READS_AS`; five atmos push lists also name `rust_device_rev`, an invalidation token bumped by setters, which is not a read
(listed under `[tokens]`, reported apart). Twelve of the 20 bodies call 27 global helpers with no `READS_FROM`; the final design
makes each an `unannotated_global` error, so `[unannotated]` pins them as a shrink-only ratchet (capability-state accessors that
E1's `cap_keys` generates, Rust sinks and pure lookups that take `READS_FROM()`, and a few state helpers that take
`READS_FROM(arg)`).

### The other semantic checks

| Lint / rule | Finds |
|---|---|
| `sem/keys` `unresolved_id` | a `STAT_`/`SRC_`/`STAGE_`/`CAP_` id, or a capability-state id (`COVER_LOST`), inside a marker that nothing declares (with a did-you-mean) |
| `unresolved_op`, `unresolved_capability` | a literal key in `extend/without/on_op/shares_effects/above/perform_op`, or `configure` |
| `text_source` | `source = "text"` or `source = null` on `hold/grant/release/...` |
| `duplicate_declaration`, `accessor_var` | a stat/source/stage/capability declared twice; a `SYSTEM_ACCESSOR` whose var is not on the system |
| `sem/handlers` `handler_unresolved`, `signature` | a named proc that does not exist; not `x(datum/act/A)` |
| `context_field` | `A.actor` in a condition, `A.dt` in a requirement (the field is checked against the hook's context type) |
| `impure` | a pure handler (or a body it follows) that writes a tracked var, or calls a setter, hold, release, grant, revoke, `rel_*` or a message |
| `requirement_return` | a requirement or condition returning text, null, a type or a non-boolean number |
| `act_try_unpaired` | an `ACT_TRY` with no `act_done`/`act_cancel` on some path (a branch testing the result for null or `ACT_PASS` is clean) |
| `context_escape` | a pooled `datum/act` stored in a var, a list, or passed with `=` |
| `output_signature` | an override of `draw/ui_data/push_to_rust/examine` whose params differ from the base declared under `code/engine/` |

`ACT_TRY` must survive macro expansion as a call the pairing check can see (`ACT_TRY`, `act_try`, `e0_act_try`; E4: if the macro
expands to another proc, add its name to `[lint."sem/handlers".lists] try_calls`). Exemptions are `lint_scopes.toml` and
`// ALLOW(keys|reads|handlers): reason`, as for every lint. Every rule has a seeded violation and a clean case in
`fixtures/sem__keys`, `sem__reads`, `sem__handlers` (held by `cargo test`).

### Writing a generator (the API E1, E3, E4 and E6 call)

A generator is a query on the semantic layer whose answer is a DM file under `code/engine/_generated/`. Add
`src/gens/<name>.rs` (build.rs finds it) with `pub fn register(reg: &mut Vec<Box<dyn Generator>>)`; copy
`src/gens/system_accessors.rs` (text only) or `src/gens/reads.rs` (uses the full model).

```rust
impl Generator for X {
    fn name(&self) -> &'static str { "x" }            // analyze gen x, and the [gen/x] tag on diagnostics
    fn output(&self) -> &'static str { "x.dm" }       // code/engine/_generated/x.dm
    fn generate(&self, cx: &GenCx, out: &mut GenOut) {
        for m in cx.markers("ACTION") {               // m.args are split at top-level commas; m.rel / m.line locate it
            out.line(format!("/datum/act/{}", m.args[0]));
            out.diag(&m.rel, m.line, "message");      // a finding; any diagnostic fails `analyze gen`
        }
    }
}
```

`GenCx` offers `markers(name)`, `keys()` (declared stat, source, stage, capability and op ids), `sem()` (the full model; a
generator that never calls it costs no parse), `handlers()` (the procs declarations name, with hook form, role and context),
`decls()` and `tree`. `GenOut` has `line`, `blank`, `doc` (a `///` line) and `diag`. A generated file gets a fixed header,
must be deterministic (sorted, no timestamps, no absolute paths) and is compared byte for byte by `analyze gen --check`, which also
fails when the file is not `#include`d in `deepquarry.dme`. Diagnostics use the engine's format, `file:line: [gen/x]
message`, and the same exemption mechanism as the lints. Put a golden next to a fixture and a test in `tests/semantic.rs`
(`BLESS_GOLDENS=1 cargo test` writes it).

`reads.dm` (`analyze gen reads`): three `GLOBAL_LIST_INIT`s of flat lists, `generated_read_names` (every interned name, id =
index), `generated_read_roots` (`READ_ROOT_HOLDER` 1, `ACTOR` 2, `HELD` 3, `TARGET` 4, then `system:<name>`) and
`generated_reads_table`: `"<type>::<proc>" = list(rank, list(root id, kind, name id, hop name ids...), ...)` with kinds
`READ_KIND_VAR` 0, `ACCESSOR` 1, `NATIVE` 2, `SYSTEM` 3. E3 reads the table at boot; nothing uses `vars[]`, `call()` or text keys at
runtime. `system_accessors.dm` (`analyze gen system_accessors`): one `/proc/<name>()` per `SYSTEM_ACCESSOR`, returning
`GLOB.<system>_service.<var>` (`SYSTEM_INSTANCE` in `sem/gen.rs`).

`ids.dm` (`analyze gen declare_ids`, E1; included early in `deepquarry.dme`, before everything that names an id): the ids the markers
declare, as `#define`s, sorted by name within each family: `STAT_<NAME>` (from 100001; a status, `units =`, also gets `STATUS_<NAME>` and
`STAT_<NAME>_IMMUNE`), `CAP_X` (from 300, for a `CAPABILITY_TYPE/DEF` whose id no hand-written define gives), `SRC_<NAME>`,
`STAGE_<GROUP>_<NAME>`, `GRAPH_X` and the capability-state ids of `cap_keys` (`COVER_OPEN`, as `CAPKEY_ID(CAP_COVER, 1)`). An id a
hand-written `#define` already gives is left alone, so the contracts' hand ids keep working. `declare.dm` (`analyze gen declare`): for
each `CAPABILITY_TYPE/DEF(name, CAP_X, [/datum/capability/x,] key =, stacks =, param = default, ...)` the datum's param vars with their
defaults, the constructor `name(params)` (a real proc, so DM checks a call's named arguments) and the registration row the engine reads
at boot; a registration row for each `cap_keys`, `STAGE_DEF`, `SOURCE_DEF` and `STATE_GRAPH`, with the `<cap>_<key>(holder)` accessor of
each state key; and, for each `CAPABILITIES(T, entries...)`, `T/declared_entries(list/into)`: the entries copied as written (so
`nameof(var)` and `PROC_REF(x)` resolve against `T`), each preceded by `entry_line(n)` so the explain tools say where it came from. Two
rewrites: `link(A::a, B::b)` (`link` is a BYOND keyword) becomes `entry_link("A::a", "B::b")`, and `configure(CAP_X, "selector", param =
value)` becomes `configure(<constructor of CAP_X>("selector", param = value))`. Declarations in files under `code/tests/` go in an
`#if defined(UNIT_TESTS)` block. A second `CAPABILITIES` list for one type is a diagnostic. DM cannot continue a macro call across lines,
so a marker that spans lines ends each line but the last with a backslash (`DECLARE_LOOT` and `DECLARE_INTERACTIONS` already do); the
generator drops the backslashes.

## Tooling gotchas

* A `Tree::memo` init must not use rayon (`par_iter`, `join`): the initializing worker steals another lint's task while it waits,
  and a stolen task that needs the same cell blocks on the init this thread is running, a deadlock. Use `sem::par_map` (plain scoped
  threads, which never steal engine work). A cold-cache run hung about one time in six before the semantic layer did this.
* Edit Rust with the Write/Edit tools. Shell heredocs and `python -` snippets through the Bash tool have
  been seen to halve backslashes (`'\\'` becomes `'\'`), which silently corrupts regexes.
* Python text-mode writes CRLF on Windows; sources here are LF (`* text=auto`).
* The old scripts take minutes on the real tree (`sys_lint` ~140 s). Use `--fixtures-only` while
  iterating and run the full parity once at the end.
* Never edit `tools/dm-health` (a different project) and do not depend on it.

## After the legacy scripts

The Python lints and the `check_grep.sh` pipelines were deleted once every lint had parity (commit
before the deletion: `git log --diff-filter=D --format=%h -1 -- tools/ci/sys_lint.py`, then use its
parent). `analyze parity` compares against those scripts, so to re-run it check that parent out in a
worktree. What remains of them is `tools/analyze/fixtures/<lint>/expected.txt` (the old scripts'
findings on each fixture tree), held by `cargo test` forever, and the ported selftests. The two
generator checks (`tools/dx/gen_capability_varmap.py --check`, `tools/dx/gen_om_notices.py --check`)
are still Python: they regenerate files rather than lint, take about 3 s each, and
`check_ratchets.sh` runs them beside the engine.
