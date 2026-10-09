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
analyze codemod list | NAME [--check|--apply|--revert] [--path PREFIX...] [--write-residue]
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
| Cache | `src/cache.rs` | `data/analyze-cache/` (or `$DQ_ANALYZE_CACHE`): per-file results keyed `(path, content hash)`, tree memo keyed by the combined hash; stamped with the engine build hash |
| Incremental stores | `src/incr.rs` | per-file facts and per-file judgements for whole-tree lints, cached on disk (see "Incremental lints") |
| Semantic record | `src/sem/incremental.rs` | what lets the semantic lints and the `reads` generator skip the 8 s parse after an edit (see "Backend and cost") |
| Runner | `src/run.rs` | Parallel run, policy judgement (`Sites` / `Ceilings` / `Hard` / `Custom`), `--changed-only`, baseline rewrite |
| Parity | `src/parity.rs` | Old script vs engine on the real tree and on `fixtures/` |
| Frontend | `src/frontend/` | `Frontend` trait: `TextFrontend` (the line scanner) and `DreamMakerFrontend` (SpacemanDMM `dreammaker`, tag suite-1.11) |
| DM helpers | `src/dm/*.rs` | Shared scanners (`dx.rs` = `_dx_dm.py`, `sys.rs` = the sys_lint family) |
| Lints | `src/lints/*.rs` | One file per lint, found by `build.rs` (no registry to edit) |
| Semantic layer | `src/sem/`, `src/gens/` | Type/proc/var resolution on dreammaker, generated reads, key resolution, handler checks, generators (see "Semantic layer") |
| Codemods | `src/codemod/`, `src/codemods/` | The phase 2.5 rewriter: call-node scanner, span edits, residue, key collisions, revert (see "Codemods") |

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

## Incremental lints (`src/incr.rs`)

A whole-tree lint is a fold over per-file facts and a per-file judgement that reads the fold. Written the old way it re-reads
every file after any edit (seconds). Written with `incr` it costs the edited file plus a merge:

```rust
// facts: f(file), cached on disk by content. Pure function of the one file.
let facts: Vec<Facts> = incr::facts("my-lint-facts", &files, facts_of);
// merge into the context, and key the context by the facts that matter
let key = incr::ctx_key(&nonempty_facts);              // deterministic: sorted Vecs / BTreeMaps, never HashMap order
let ctx = merge(&facts);
// judge: f(file, ctx), cached by (file content, key): an edit that changes no fact re-judges one file
let results: Vec<R> = incr::keyed("my-lint-judge", key, &files, |f| judge(f, &ctx));
```

`incr::two_phase` wires the three steps. Facts and results must round-trip through bincode (`Serialize + Deserialize + Default +
PartialEq`; `Default` means "nothing found" and costs no space; store a rule index, not a `&'static str`). Allow-annotation
uses recorded through `sys::kept_recorded` inside the closure are captured with the result and replayed on a hit. A store with
1,024 files or more is split in 16 shards inside one file, so an edit re-encodes one shard. Values are encoded with bincode
variable-length integers (`incr::ser`/`incr::de`). Worked examples: `sys_sfx.rs` (the smallest), `dm/ownership_index.rs`,
`dm/dx.rs` (a shared index built from per-file facts), `sem/decls.rs`. Work that happens *outside* the cached scan
(`post_judge`, `finish`, an index rebuilt in `judge`) is not cached: check a lint with `DQ_ANALYZE_TRACE=1` (a warm run should
report about 0 files loaded, a one-file edit about 1). `Policy::Sites` fingerprints compare the normalized source line of each
baselined site; those line texts are cached too (`linetext.bin`), so judging never loads a file only for that.

Per-run fixed costs worth knowing: the selftests run once per engine build (a marker in the cache); `check_grep` compiles its
regexes only when a scan really runs; the tree walk is parallel by directory; the whole-tree prewarm (read and strip every file)
runs only when more than 64 files are new or changed.

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

A tree whose declarations name no handler pays a scan, never a parse: `handlers::analyzed()` returns `None` before
building the model. The incremental compiler's analysis API replaces dreammaker by implementing `Sem`'s small surface
(`ty`, `var_decl`, `proc_ref`, `proc_body`, `owner_candidates`, `def_at`); no rule names a dreammaker type outside `src/sem/`.

**The semantic record** (`src/sem/incremental.rs`, `data/analyze-cache/sem-cache.bin`) keeps the parse off the one-file-edit
path. A full run stores, beside the results of `sem/reads`, `sem/handlers` (the declared-handler part) and the `reads`
generator: per included file its content hash, a digest of the structure it contributes (var declarations, proc
definitions and parameter lists: no bodies, no line numbers), the var names its procs write, and a digest of its
comment-stripped text; plus the **footprint** (every file whose definitions the analysis consulted, recorded by `Sem` as it
answers: 18 files for 65 handlers) and each type's location. A later run reuses the results when (1) `deepquarry.dme`, the
declaration text (`Decls::key`) and `code/__defines/**` are unchanged, (2) the included file set is unchanged, and (3) every
changed file is outside the footprint, has no `#define`/`#undef`/`#include`, and either has the same comment-stripped text
(a comment or blank-line edit: no parse at all) or, parsed alone with the defines (about 0.15 s), has the same structure
digest and written names, a bare type header the old text did not have being a change. Any doubt is a miss, never a stale
hit. A change inside the footprint, or to the structure, runs the full model (8 s) and refreshes the record.

### How `analyze gen` stays fast

A generator has a `stage()`: 0 for one that reads only declarations and file text, 1 for one that reads another generator's output
or builds the full model (`reads`, `derived_reads`). `analyze gen` runs stage 0 until nothing is written, reloads the tree, runs
stage 1 once on the settled files, and then proves stage 0 is still fresh against what stage 1 wrote (stage 1's own output is no
generator's input, so it is not run again: running it again would parse the full model a second time). So a merge that changes
declarations parses the model once, not once per pass. A run that converged records `data/analyze-cache/gen-state.bin`: the
analyzer build, a digest of every file the generators can read (and `deepquarry.dme`) and the content digest of every output. The next
run with the same inputs and intact outputs prints the fresh files and returns (about 0.4 s, from the tree walk), whatever else
changed (`lint_scopes.toml`, a lint's baseline). `DQ_ANALYZE_TRACE=1` prints the passes, each generator's render time and
whether the model was built.

**The shared store.** A converged run also copies its outputs into `E:/dq-cache/gen-store/<key>/` (`DQ_GEN_STORE`, `off` disables it; the 40 newest
entries are kept), keyed by the analyzer build and the content of every file the generators read except the generated files themselves, so the key is
the same before and after they are written. A run that meets a key the store holds (a new worktree of a commit another worktree generated, a merge
of one lane whose lane-ready run generated the same tree, a hand-edited output) copies the files back after checking each against the manifest's digest,
instead of generating them: a fresh worktree's first `gen` goes from 28-80 s to about 1 s. Only clean runs (no diagnostic) are stored.

The whole-tree scans the generators do (the defined types of every file, which files mention a notice type, `#define` names,
`SYSTEM_DEF`) read the `.dm` tree on all cores first (`Tree::prewarm_dm`); the first two are per-file facts cached by content
(`gen-defined-types`, `notice-mentions`), so a run after an edit reads only the edited files for them.

### `analyze look-keys` (the look plan)

`analyze look-keys [--out FILE] [--explain TYPE] [--no-cache]` writes one line per concrete /obj, /mob and /turf type: its key (a
digest of everything that can change its look rows) and the vars a state probe should write. Cold it parses the model (8-15 s) and
walks the draw closure of 6,200 distinct closures (about 15 s: edges are interned, the visited sets are bitsets, the integer tables
use a multiplicative hasher). `data/analyze-cache/look-keys.bin` makes the next run incremental:

| The edit | Cost |
|---|---|
| nothing | 0.5 s (the stored rows) |
| comments, blank lines, a file the model does not include | 2 s (no row can move) |
| a proc no closure contains, or var values no chain type is assigned (most gameplay code) | 2 s (a partial parse of the changed files) |
| a proc in some closure, or a var value of a chain type | one full model parse (8-15 s), then only the rows whose closure holds a changed proc, or whose chain holds a type assigned different values, are recomputed |
| a new or removed var, proc or type, a `#define`, a changed declaration marker, `deepquarry.dme`, a salt file, a `DECLARE_APPEARANCE`/`abstract_type` line, a different analyzer build | everything (cold cost) |

The cache records per row the closure as a bitset over the table of procs some closure contains (each with a digest of its text), per
included file the structure facts of `sem::incremental` (shape, comment-free tokens, bare headers, directives, located types) and a digest
of the var values it assigns to each type. A partial parse of just the changed files (`Sem::build_partial`) must give the same shape and
types and says which closure procs changed their text and which types were assigned different values. The tests
(`tests/look_keys.rs`) compare the incremental rows with a full computation after each kind of edit; `DQ_LOOK_TRACE=1` says why an edit was
refused and prints the phase timings.

A key covers the type's chain (var values, declarations), the procs of its draw closure, its icon sources and the look builder
(`SALT_FILES`: `appearance.dm`, `appearance_builder.dm`). The closure never enters a *sink* (`SINK_DIRS`, `SINK_NAMES`,
`SINK_PREFIXES` in `look_keys.rs`): movement, lifecycle, messaging, logging, `code/engine/`, controllers, admin and test code cannot
change a drawn look, and the pin rows are made by writing vars and calling the draw, so an edit there moves no key. Hashing the
whole file of `/atom/update_icon` (`_atom.dm`) and the absolute checkout path inside `__FILE__`-style macro expansions were what
once moved all 21,000 keys on nearly every merge; neither is hashed now. A proc that really is plumbing every draw goes through
belongs in `SALT_FILES`, not in a closure.

### Declarations the analysis reads

Markers expand to nothing in DM (`code/__defines/engine/markers.dm`), so they are read from comment-stripped text with
balanced parentheses (a marker may span lines; a marker in a comment is documentation, not a declaration):

| Marker | What the engine takes from it |
|---|---|
| `STAT(T, name, RULE, ...)` | stat `STAT_<NAME>` on `T`; `name` is a stat var (a plain read) |
| `SOURCE_DEF(name)` / `STAGE_DEF(group, name)` | `SRC_<NAME>` / `STAGE_<GROUP>_<NAME>` |
| `CAPABILITY_DEF(name, CAP_X, ...)` / `CAPABILITY_TYPE(name, CAP_X, /type, ...)` | capability key `name`, id `CAP_X`; every `op("x", ...)` inside is op key `name.x` |
| `cap_keys(CAP_X, OPEN = ..., ...)` | state ids `<NAME>_OPEN` for the capability whose id is `CAP_X` |
| `CAPABILITIES(T)` + indented entries | the holder type `T` of the handlers named inside; `op("x")` is op key `x` |
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
| `instead`, `adjusts` | `/datum/act/action` | take-over, modifier |
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

**The spike (oracle).** `tools/analyze/oracle/spike.toml` pins 18 real handlers; `cargo test --test oracle` and `analyze sem
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

`ACT_TRY` must survive macro expansion as a call the pairing check can see: `ACT_TRY(E, name, ...)` expands to `act_<name>(E, ...)`, and
the lint adds `act_<name>` for every non-FIXED `ACTION(name, ...)` marker itself (`ACT_TRY`, `act_try` and `e0_act_try` stay; any other expansion
name goes in `[lint."sem/handlers".lists] try_calls`). A `then()` or `when()` inside `instead`, `adjusts`, `on_notice`, `on_op` or `on_change`
runs in that hook's context: an action's handler may read the typed fields of any `ACTION()`, a notice handler those of the notice type named in its `on_notice`. Exemptions are `lint_scopes.toml` and
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
must be deterministic (sorted, no timestamps, no absolute paths) and is compared byte for byte, so `analyze gen` rewrites only a
file whose text changed (an unchanged tree keeps its mtimes and the build's .dmb caches); `analyze gen --check` writes nothing.
Both fail when the file is not `#include`d in `deepquarry.dme`. The output is not committed: every build runs `analyze gen`
first (tools/build/build.ts `GenTarget`). Diagnostics use the engine's format, `file:line: [gen/x]
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
each state key; and, for each `CAPABILITIES(T)` block, `T/declared_entries(list/into)`: the entries copied as written (so
`nameof(var)` and `PROC_REF(x)` resolve against `T`), each preceded by `entry_line(n)` so the explain tools say where it came from. Two
rewrites: `link(A::a, B::b)` (`link` is a BYOND keyword) becomes `entry_link("A::a", "B::b")`, and `configure(CAP_X, "selector", param =
value)` becomes `configure(<constructor of CAP_X>("selector", param = value))`. Declarations in files under `code/tests/` go in an
`#if defined(UNIT_TESTS)` block. A second `CAPABILITIES` list for one type is a diagnostic. DM cannot continue a macro call across lines,
so a block is a header whose entries are the indented statements under it (`CAPABILITIES(T)`, `STATE_GRAPH(graph)`; `CAPABILITY_DEF` is
read the same way): `decls` joins the entries with commas in place of the entry-ending newlines (same length, so lines stay right) and every
reader sees one argument list. A `section(name, "doc")` line in a block opens a section: the entries after it (to the next section or the
block's end) are written with `entry_line(line, "name")`, so Explain Type and Explain Interaction print `file:line section name`; the header
itself is no entry, and an empty, misnamed or repeated section is a diagnostic. `BUNDLE(name)` is gone (`declaration_block`'s `bundle` rule
rejects it). Reuse is a capability or a plain proc: `decls` reads a global `/proc/name(...)` whose first statement is `return list(...)` of
entries as an `ENTRY_PROC` marker, so op keys (`sem_keys`), handler discovery, `ui_types` and `op_order` see into a `name()` entry the way
they read a block. The legacy backslash list is still read, for the fixtures. `links(A::a, B::b)` is the block spelling of `link`
(a BYOND reserved word).

`stats.dm` (`analyze gen stats`, E3): for each `STAT(T, name, RULE, base =, reapply =, units =, formula = PROC_REF(x), reads = list(...), schema =,
virtual = TRUE)` the stat's var on `T` with the rule's base as its default (not when `T` or an ancestor already declares a var of that name, when the
name is one of BYOND's own, or with `virtual = TRUE`; the line carries `// ALLOW(base_vars)`), a `__stat_<name>()` proc returning the stat's row, and
the registration the stat layer reads at boot. A row declared under `code/tests/` is written inside `#if defined(UNIT_TESTS)`. The generator ignores its
own previous output when it decides which vars a type already has. `system_accessors.dm` does the same for accessors declared under `code/tests/`.

`ui_types` (`analyze gen ui_types`, E2/E5): for each `CAPABILITIES(T, ...)` that names `interface("Window", ...)`, one TypeScript file
`tgui/packages/tgui/interfaces/generated/<Window>.d.ts` (not a DM file: `Generator::files()` returns `(path, text)` pairs, compared byte for byte
by `--check` and not looked for in `deepquarry.dme`). `ui_shape(var, ...)` lists the data fields, each typed from the tracked var's schema
(`TRACKED_SCHEMA(T, var, schema)` or `SCHEMA(T, var, schema)`), and the `ui_act()` ops of the same list give the actions type with their `arg()`s
(`arg("pressure", from = nameof(target_pressure))` takes the var's schema). The doc comment on every field is the schema's range text, the
text `schema_range_text()` returns at runtime (`/** num 0..MAX_PUMP_PRESSURE step 1 */`), so E0 proof 10 can compare the two; the TypeScript type
of a numeric field stays `number`. `tools/build/lib/ui_types.ts` (the legacy UI-table dump) leaves a file with this generator's header alone.
A `handlers/signature` note: the handler of an op with a `ui_act()` or `topic()` binding takes the op's declared `arg()`s after `A`.

## Codemods (phase 2.5)

`analyze codemod` rewrites the tree one legacy form at a time (doc/rewrite/final_api.html, section 19, phases 2.5 and 3). A codemod is
one file in `src/codemods/` (build.rs finds it, like a lint) and a directory `tools/analyze/codemods/<name>/` with its fixtures and its
committed `residue.json`.

```
analyze codemod list
analyze codemod NAME [--check] [--path PREFIX...] [--write-residue] [--sites]    dry run on the tree
analyze codemod NAME --apply [--path PREFIX...]                                   rewrite files, write data/codemod/NAME/revert.json
analyze codemod NAME --revert                                                      undo the last --apply
```

**How it finds a site.** The dreammaker parse (`Sem`) reports every unscoped call of the codemod's callees with its line, column and
argument count, so a name in a comment, a string, `PROC_REF(x)` or a method of the same name is never a site. `codemod/scan.rs` then
finds the byte spans of the callee and each argument on the file's own text (on `strip::sanitize`, so a comma in a string or a comment is
not structure); the parser's argument count has to agree with the scan or the site is residue. The codemod turns the node into `Edit`s:
span replacements and insertions, never a re-print, so comments, line breaks, indentation and CRLF outside the touched tokens survive,
and nested calls compose in one pass. `src/codemods/om_after.rs` (reorders arguments, adds `with = list(...)`) and `own_set.rs` (a rename)
are the two shapes to copy.

**What the gate checks** (`cargo test --test codemods`, per codemod): every `fixtures/<case>.in.dm` rewrites to `<case>.out.dm`; an
`already_converted` case is a no-op; a second run on the output changes 0 lines (idempotent); two runs are byte-identical
(deterministic); a CRLF copy of every fixture comes out CRLF; every edit has an exact inverse and no line is added or removed; the
reason codes of the residue sites match `<case>.residue`; and every reason code the codemod declares has a negative fixture. Fixtures
compile against `_stubs.dm` in the same directory (the legacy and new procs the cases call).

**Residue.** A site the codemod will not rewrite carries a reason code (`Codemod::reasons()`, plus the framework's: `not_in_ast` for a
legacy call the parser did not return as a call (a macro body, an inactive `#if`), `reference` for the name passed as a value,
`scan_failed`, `arg_count_mismatch`, `edit_conflict`). `--write-residue` writes `residue.json` (the integer, the count per reason, one line
per site: file, reason, normalized text; no line numbers, so edits elsewhere in a file do not churn it). `--check` exits 1 for a residue
site not in the committed file, a missing file, or an unresolved key collision. Framework and test files (`FRAMEWORK_PREFIXES`, and what
the codemod's `excluded()` adds) are counted as `excluded`, never as residue, as in the count method.

**Keys.** A codemod that gives or keeps a key (`after(..., key =)`, later an op key) returns `KeyUse`s; `codemod/keys.rs` groups them by
`(owner, key)` and reports every key that names two handlers. A collision between keys the old form already had is `preserved` (the
conversion keeps today's behaviour); one involving a synthesized key is `unresolved` and fails the gate until the codemod resolves it
(`extend()` when the old semantics appended, a macro-kind prefix when the entries were independent). `keys.json` is written beside
`residue.json` when a codemod keys anything.

**Revert.** `--apply` records, per changed file, the hash before and after and the inverse of every edit; `--revert` restores the files
only if each is still exactly what the codemod wrote. After the step is a commit the recipe is `git revert <commit>`; with later steps
stacked on it, re-run from `pre/<step>` (doc section 19, "Revert recipe").

**Scope today.** `om_after` (also `after_slot`), `own_set`, `own_add`: the three highest-volume forms whose target is on master
(`after()`, `rel_set()`, `rel_add()`). The `om_ask` and `om_hook` codemods were deleted with the OM framework (their sites were converted
by hand); `INTERACT_*`, `UI_ACT`, `TOPIC_ACTION` need `op()`.

## Tooling gotchas

* `Tree::memo` runs its init on a fresh OS thread inside a rayon pool of its own (`tree::run_isolated`), so an init may use
  `par_iter` and `incr::facts`. The waiting caller is blocked in a plain join (it never steals a lint job while it holds the
  cell), and the private pool holds only that init's work (a worker waiting inside one init can never steal another init's
  closure, which could need the cell it is building). That removes the old deadlock (a rayon call under a memo init stole a lint
  that asked for the same cell). The one rule left: a task running inside an init must not itself call `Tree::memo`. A memo
  state dump for a hang: `DQ_ANALYZE_WATCHDOG=<seconds>` prints which memos are initializing/waiting and exits 99.
* Debug aids: `DQ_ANALYZE_TRACE=1` (phase times, memo builds, files loaded, record misses), `DQ_ANALYZE_TRACE_SPANS=1` (each lint's
  start..end), `DQ_ANALYZE_TRACE_INCR=1` (each incremental store's time), `DQ_ANALYZE_TRACE_LOAD=1` (backtrace of the 300th lazy file
  load: finds a lint that reads the whole tree on a warm run).
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

`actions.dm` (`analyze gen actions`, E4): for each `ACTION(name, typed fields..., FIXED, notice = /datum/notice/x)` the act type `/datum/act/<name>` (parent
`/datum/act/action`, or the parent action for a `hit/projectile` name) with its typed fields, `act_<name>(holder, fields...)`, the past-tense notice with
the same fields (a var the tree already declares on that notice type is not declared twice), `make_notice()` on the act, and the registry
`action_notice_types`; for a FIXED action no act type and `publish_<name>(holder, fields...)`. Past tense: `fall` -> `fell`, `insert` -> `inserted`,
`equip` -> `equipped`; a name that already reads as past tense (`hit`, `stumbled_into`, `round_started`) is kept. A field named `origin` is declared
`origin_turf`; any other field every act carries is a diagnostic; the `op` action keeps the op context as its act. The declare generator also rewrites `adjusts(packet.amount, ...)` and `on_change(nameof(a.b), ...)` so the path is text.
