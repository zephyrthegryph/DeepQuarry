# Retained frontend revision

Status: design plus staged implementation, lane `tools/dmb-redesign`, started 2026-10-16.
Follows `structural_change_set.md` (change set, stable numbering) and the 2026-10-16 addendum of
`doc/rewrite/native_compiler_issues.md` ("What the 2.5 s target still needs").

## Goal and targets

With a resident daemon on the production tree (`deepquarry.dme`):

| Edit | Target |
|---|---|
| body edit (including string literals), new var or proc on an existing type | at most 2.5 s |
| new type, removed var or proc, `#define` used outside a body | at most 5 s, no full compile |

Also: a persistent filesystem watcher instead of per-request directory sweeps, incremental
publication (write only changed sections), and no memory regression (about 8.3 GB private after
edits today; under 8 GB if possible).

Incremental output only has to be semantically equivalent to a fresh native build (`dmb-equiv
--ignore-debug`), never byte identical (2026-10-14 decision, `structural_change_set.md` addendum).

## Where a request spends its time today

Measured on the production tree, resident daemon, private namespace (`DMB_DAEMON_NAMESPACE`),
machine shared with other lanes (single runs vary by 1.3x). Body edit, seconds from request start:

| Stage (`request_mark` names) | Cost | What it does |
|---|---|---|
| session validation | 0.5-1.1 | latest session record, bulk directory proofs (1,359 listed and 651 fallback directories), input validate |
| input scan | 0.25 | canonicalize about 5,900 source paths, prepared-input hits |
| frontend | 2.1-2.3 | directive planning 0.61, expansion 0.30, source indexing 0.11, declaration parsing 0.71 (ordered merge 0.17), origins 0.19, tree resolution 0.08, body indexing 0.14 |
| source checks, shape | 0.35 | bodies, text, braces, skeleton hash, per-body digests |
| resources and maps | 1.0 | resource demand (lex of the expanded text) 0.31, input validation 0.35, retained order 0.07 |
| patch admission, startup facts | 0.65 | early admission, roster, startup keys, plan, inventory, spellings |
| ABI preparation | 0.9 | scheduler over 87,014 units: collect, qualify, validate, waves, certify |
| lowering, link, splice | 0.1 + 0.1 | one body |
| publication | 0.55-0.85 | pair store write (77 MB), install, resource manifest |
| finalization | 0.2 | declarations, generation, memo publication |

Every stage except the one body being lowered is a whole-program pass whose answer is almost
always "unchanged". Item-level reuse (memo keys, receipts) is already high; the cost left is
visiting every item to find that out. Trimming those passes cannot reach 2.5 s; the passes must
stop being visited.

## Model

One retained revision per daemon slot, edited in place by a **change set** instead of rebuilt and
re-validated:

```
Revision {
  files:       per source file: bytes digest, directive digest, interval table
  plan:        directive plan (intervals, per-interval recorded actions and macro reads)
  regions:     expansion regions with output ranges (prefix-summed, so a length change is O(log n))
  chunks:      declaration chunks keyed by content, with contributions
  tree:        semantic tree, occurrence index, member arena (existing retained semantic state)
  bodies:      body table (expanded span, source position, digest)
  demand:      resource demand per region (literals found in that region's output)
  facts:       startup facts, ABI units, admitted per unit
  watch:       filesystem epoch the revision was validated at
}
ChangeSet { files: set<path>, kinds: Body | Declaration | Directive | Include | Resource | Map | Unknown }
```

A request is: (1) ask the watcher which paths changed since `watch.epoch`; (2) classify them into
a `ChangeSet`; (3) hand each stage the change set. A stage that cannot prove it can edit in place
reports `Unclassified(reason)`, logs `change set: <stage> full (<reason>)` and runs its present
whole-program path, so correctness reduces to "the full path is correct" plus "an in-place edit
equals what the full path would produce".

### The invalidation unit for one changed file

From the frontend map (passes in `dm-tree/src/frontend_pipeline.rs`):

* **Directive planning** is one serial state machine (macro environment, conditional stack,
  include-once set, `FILE_DIR`). An interval's recorded actions depend on its bytes, its incoming
  conditionals and the macros it read. If the changed file's directive lines (the `#...` tokens
  and their order) are the same, every interval of every other file replays to the same actions,
  so the plan is the old plan with that file's intervals re-lexed. If a `#define`, `#undef`,
  `#if`, `#include` or `#pragma` line changed, the invalidation unit is the file plus every later
  interval whose recorded `reads` name a macro whose definition changed (a reverse index
  macro -> reader intervals, kept with the plan).
* **Expansion** is per region: its bytes, the macros it reads, `__FILE__`/`__LINE__` inputs. The
  unit is the file's regions plus the readers of changed macros. Joined-text offsets after the
  edit shift by the length delta; they are kept as (region, offset) pairs bound by prefix sums, so
  nothing downstream stores an absolute offset it cannot rebind.
* **Declaration parsing** chunks are content-addressed and independent of other files; the unit is
  the chunks overlapping the changed regions plus boundary resynchronisation (the grammar scan
  already reuses descriptors).
* **Tree resolution**: for body-only change sets the skeleton is identical, so the retained tree
  is reused as is. Declaration change sets feed the existing splice (`metadata_splice.rs`), whose
  work is bounded by `affected_types()`.
* **Bodies**: a body's key is (owner, name, occurrence); positions are a side table rebound by the
  piecewise line map of `body_patch_lines.rs`.

### Consumers keyed by the change set

| Consumer | Today | With the change set |
|---|---|---|
| resource demand | lex of the whole expanded text (0.31 s) | per-region literal sets; changed regions re-lexed, union maintained |
| resource/map validation | proofs over every recorded folder (0.35 s) | watcher says no resource or map path changed |
| startup facts | rebuilt from all bodies and declarations (0.65 s) | reused when no changed body is `guarded` (static/global declaring) and no declaration changed; changed bodies only re-keyed |
| ABI units | scheduler over 87,014 units (0.9 s) | units of unchanged owners with clean read domains keep their admission; only changed units re-run |
| publication | 77 MB pair write plus install plus 218 MB RSC reuse checks | write the changed byte ranges and the string/list tail (see below) |

### Filesystem watcher

A per-slot watcher (Windows: `ReadDirectoryChangesW` on the project root and every recorded input
directory outside it, through raw FFI like the existing bulk proofs; elsewhere the present sweep)
maintains an epoch counter and a dirty set.

* **Sync cookie.** A request first creates a unique file in the watched root and waits for its
  event; events on one directory handle are ordered, so everything written before the request has
  been delivered when the cookie arrives. This closes the save-then-build race.
* **Overflow and errors** (zero-length completion, `ERROR_NOTIFY_ENUM_DIR`, handle loss, rename of
  a watched directory) mark the root unknown; the next request runs the full sweep and re-arms.
* **What it replaces.** `BulkFileSystemProofs::capture_snapshot` and `InputSnapshot::validate_*`
  re-stat and re-list on every request. With a healthy watcher, validation is: drain events, restat
  only the dirty paths, keep the retained proofs for the rest.
* **Safety net.** Publication admission (`runner_freshness::admit_live`, early admission on a
  worker thread) still restats every captured input live. A watcher that lost an event can at
  worst make that admission refuse and rebuild; it cannot publish a stale build.

### Incremental publication

The pair store is immutable and content addressed, so a patched build cannot edit a stored pair
in place. Two writes of 77 MB per request are the DMB (pair store, then the conventional copy);
the 218 MB RSC is reused when its identity is unchanged. Plan: (1) hard link the store entry to the
conventional path instead of a second copy where the volume allows it; (2) assemble the new DMB
from the retained image by copying unchanged sections (class table, procedure table, variables,
untouched list rows are one contiguous run each) and writing only changed list rows and the string
table tail, using the section offsets the encoder already tracks for `patch_rows`.

### Resource listing changes (coordinator request, 2026-10-16)

The daemon-ns lane saw body patches declined with `non-text input changed: resource folder
listing` because the icon repack rewrites `icons/gen` between compiles. That would disable
patching on nearly every real build, so the resource input of the patch base must stop being a
folder listing:

* **Key by what the compile consumed.** A patch base records, instead of `FolderListing`s, the
  resolved resource references of the build (referenced file -> content digest, from the resource
  catalog / generated icon manifest) plus, per search folder, only the answers lookups received
  (found at path P with digest D, or proven absent). Decline only when a consumed answer changed.
  A listing change that adds, removes or rewrites an unreferenced file (the common repack case)
  leaves every answer intact and does not decline.
* **Repack churn.** `icons/gen` files are rewritten with identical bytes when sources are
  unchanged; the watcher (stage 2) reports the event, the stage 3 check compares digests of the
  referenced files only, so an identical rewrite is a no-op.
* **Changed references** (a referenced file's bytes differ, or a new literal resolves to a new
  file) patch incrementally: the resource tables are append-extended like strings (stage 1), the
  archive identity changes and the RSC is re-published, the DMB code of units that embed the
  resource index is relowered through the existing body patch path.
* Stage 3 is therefore reordered ahead of stage 2: "resource input keyed by consumed answers"
  first (it removes a full-compile cause on every real build), then the watcher.

### Structural edits

Added procs and vars append (landed). Remaining: new types (append the class when fresh
first-encounter order puts it last, else relink class order), removed members (tombstones, dropped
from class lists; compaction when tombstones exceed 5 % of a table), `#define` used outside a
body (re-expand only the reader regions, then the declaration path above).

## Stages and status

Each stage lands as its own commit with: `dmb-equiv --ignore-debug` patched vs fresh native
(strict order where it holds), boot gate under `DQ_COMPILER=native DQ_COMPILER_STRICT=1`, and no
new dmbc / dm-tree test failures.

| Stage | Content | Status |
|---|---|---|
| 0 | baseline timeline and measurement scripts | done |
| 1 | body edits that change string literals patch (append table strings, units' string footprint split from entry footprint) | done (see results) |
| 2 | resource input of the patch base keyed by consumed answers and referenced-file digests (no decline on icon repack listing churn) | next |
| 3 | watcher and cached directory proofs (landed); per-region resource demand (tried: parallel split lex, correct but no measurable gain, not landed) | partly done |
| 4 | startup facts and ABI units reused for body-only change sets | |
| 5 | frontend revision edited in place for body and declaration change sets | |
| 6 | incremental publication | |
| 7 | new types, removed members, defines used outside bodies | |

Results and timings per stage are appended below as each stage lands.

## Results

Production tree, resident daemon (private namespace), machine shared with other lanes. Seconds,
wall time of the client call.

| Edit | Before this lane | After stage 1 and 2 | Path |
|---|---|---|---|
| unchanged rebuild | 1.6-2.0 | 1.6-2.0 | session hit (not touched) |
| body edit, no string change | 8.2-9.1 | 8.2-9.1 | patch (not touched: stages 3-6 do that) |
| body edit changing a string literal | 22.8-25.1 (full compile) | 6.5-8.4 | patch, string append |
| body edit with line shift and a changed literal | full compile | 6.5-7.2 | patch, string append |
| body edit after a resource listing changed (icon repack) | full compile (reported by daemon-ns lane) | 8.2-10.6 | patch |
| new proc / new var | 9.7-10.8 | unchanged | append patch |
| removed member, new type, `#define` outside a body | 20-30 | unchanged | full compile |

Equivalence: `dmb-equiv --ignore-debug --strict-order` (and with debug lines) of the patched output
against a fresh native one-shot compile (`DMB_BODY_PATCH=0 --no-cache --no-daemon`) is EQUIVALENT
for: a string edit, a string plus body edit with and without a line shift, and a body edit after
an unreferenced file was added to and removed from `icons/gen`. `six_session_contract_tests`
gained `string_literal_edits_patch_and_match_fresh_bytes`; all 17 six-session tests pass, and
`cargo test -p dmbc --lib` has the same 24 failures as master (994 passed).

### Stage 1: string literals

`PatchRecord::footprint` split the old `inventory` part into `inventory` (entry key, slot aliases)
and `strings` (the unit's own literals). A unit whose footprint differs only in `strings` or
`value_strings` no longer declines: its string entries extend the retained `LinkTables` append-only
(`LinkTables::extended`), the changed code rows and the new strings go through `patch_model`
(model edit, list-row reuse encode), the base's unit record is replaced, and old strings stay
unreferenced (counted for compaction by a later stage). `DMB_STRING_PATCH=0` restores the decline.

### Stage 2: resource listing churn

`InputSnapshot::non_text_difference_with(other, listings)`: the folder listings and negative
lookups are compared only when the resource archive identity changed. A listing records every name
in a folder, so an icon repack that adds, removes or rewrites an unreferenced file changed it on
nearly every real build. A listing matters only through what it resolved; resolution results are in
the archive identity, the search context is the search paths alone, and consumed files are still
compared by content.

### Not done

Stages 3-7 of the table above (watcher, per-region resource demand, startup/ABI reuse, in-place
frontend revision, incremental publication, new types and removed members). The body-edit
timeline above (frontend 2.1-2.3 s, resources 1.0 s, startup+ABI 1.5 s, validation 0.5-1.1 s,
publication 0.8 s) is unchanged, so the 2.5 s and 5 s targets are not met. Memory was not
re-measured (no change to retained state beyond one extended link table per string patch).

### Stage 3: watcher (lane `tools/dmb-redesign-2`)

`fs_watch.rs`: the daemon (never a one-shot) watches the project root with `ReadDirectoryChangesW`
(raw FFI, recursive, 4 MB buffer, changes buffer per handle between calls). Each request runs a sync
cookie (`.dmbc/watch-cookie-*`) before session validation; the cache of directory proofs, and of
directory absences (a failed open is cached too), is invalidated by events (the containing
directory, the path, and its subtree for anything but a plain modification) and cleared on overflow,
read failure or a cookie timeout. A proof is cached only if no event arrived while it was captured.
Publication still restats every captured input live. `DMB_WATCH=0` disables it,
`DMB_WATCH_VERIFY=1` recaptures every cached directory and logs mismatches (none seen on the
production tree over six requests, 5,182 verified directories). The sweep also assembles its proof
maps once per distinct parent instead of once per file.

Session validation, idle between edits (marks `session.*`): proof capture 0.6 s to 0.19 s, whole
validation 0.5-1.1 s to 0.28 s. Directory capture itself is 0.02 s; the remaining 0.2 s is building
the 13.7k-file stamp map (`proofs.exact_built`).

Also landed: a body patch no longer declines when no body changed (a comment or spacing inside a
body); the base just advances. Test `comment_inside_a_body_patches_without_relowering...`.

Next-largest costs (body edit, quiet run): frontend 2.1 s, resources and maps 0.9 s, early admission
snapshot merge 0.44 s, publication 0.7 s, ABI scheduler 0.5 s, startup facts 0.4 s.

## Frontend revision: concrete design (lane `tools/dmb-redesign-3`)

Inventory (from reading `dm-preprocess` and `dm-tree`; see also the pass table above). The frontend
already retains content-addressed chunk facts, region expansion records and the semantic state, and
a request still visits everything: planning 0.6 s, expansion 0.3 s, source indexing 0.1 s,
declaration parsing 0.7 s, origins 0.19 s, tree 0.08 s, bodies 0.14 s. State holding absolute
offsets into the joined expanded text: `receipts[].output`, the origin rows (`output_start/end`; the
row index is the `output_line`), `BodyOccurrence.expanded_span`, `issued_body_codes.termination`,
the grammar descriptors. Position independent: chunk contributions (rebound by offset), the tree and
occurrence table when the skeleton is unchanged, `plan` regions (source spans are per file),
`files`. Tokens are not retained (`expand_regions_text`). Identity binding: `ColdFrontend` is a
fresh `Arc` per request and startup facts, body inputs, the callable roster and the source export
mapping are bound to it by pointer (`issuance`, `ptr_eq`), so reuse across requests means
re-issuing against the new instance, not mutating one in place.

Decision: every request still builds a new `ColdFrontend` value; what changes is how its parts are
made. The flag is `DMB_FRONTEND_REVISION`: `0` (today), `verify` (build both, compare, use the full
result), `1` (use the incremental result; fall back to the full build on any unmet precondition).
The default flips to `1` only after `verify` shows no difference over the whole production tree and
the full edit matrix.

Change set: the files whose prepared source differs from the previous frontend's `plan.source_texts`
(`Arc` pointer compare, 5.9k entries). The previous frontend is held by the host (the same `Arc`
the query state already retains).

Steps, each landing alone with `verify` proof:

* **F1, plan and expansion for a directive-free leaf file.** Precondition for every changed file:
  one non-suppressed occurrence, a `.dm` leaf (no child occurrences), one region with one segment and
  no effects, no line starting with `#` (after whitespace) in the old or the new text, no planner or
  expansion diagnostics. Then the new plan is the previous plan with that file's text, line starts,
  region lines and span, and `eof_cursor_line` replaced. The new lines come from the real planner run on
  a one-file synthetic project (so the line splitting is the planner's own); the macro environment
  is the previous segment's. The new expansion is the previous one with the file's region
  re-expanded through the region memo, the joined text spliced, the origin rows after it shifted by
  the byte and line delta (compact records, one copy), receipts rebased. Every provider read the
  full planner would make is still issued so the input capture records the same files.
  Verify compares plan and expansion structurally and by hash with the full pass.
* **F2, declaration parsing.** Reuse of the grammar scan and ordered merge for chunks outside the
  changed range: chunk contributions are position independent, so the merge splices the changed
  chunks into the retained ordered list and rebinds offsets by a prefix sum.
* **F3, origins, body indexing, tree.** Same splice for provenance, `collect_bodies` and tree
  resolution (skeleton unchanged: reuse the tree; changed: the metadata splice).
* **F4, issuance.** Startup facts, ABI units and the callable roster re-issued against the new
  instance for unchanged units instead of recomputed (the structural change set decides which units
  are dirty).
* **F5, directive-bearing files and include structure** (a `#define` edit, an added include).

### F1 results (plan and expansion edited in place)

*Superseded 2026-10-25 (`incremental_core.md`, "Frontend queries, step 3"): the single-file edit path and `DMB_FRONTEND_REVISION` are deleted; the plan is patched from the query database's change log (any changed subtree, directives included) and adopted subtree by subtree, expansion copies the regions the plan copied. What follows is the history.*

Landed behind `DMB_FRONTEND_REVISION` (`0`/unset: off, the default for now; `verify`; `1`).
`dm_preprocess::regions::{plan_regions_edit, expand_regions_edit}` (`regions/edit.rs`), the origin
arena splice (`ExpandedOriginArena::spliced`), the previous revision kept in `RetainedSemanticTree`
(`remember_frontend`), and the hook in `frontend_pipeline.rs`.

Proof: `edit_tests.rs` (edited plan and expansion equal the full ones through a chain of leaf edits
including an emptied file; directive, conditional, manifest and previously-directive edits decline);
`verify` on the production tree for a same-length and a line-shifting edit logged "plan edit equals
the full plan" and "expansion edit equals the full expansion" (the comparison covers every region
header, line, span, every origin row field, receipts and the joined text; the macro environment is
compared deeply for the edited regions only, since comparing every region's bindings took longer
than the build); `DMB_FRONTEND_REVISION=1` output of a patched edit is `dmb-equiv --ignore-debug
--strict-order` EQUIVALENT to a fresh native build. dm-preprocess 148, dm-tree 324 tests pass; the
dmbc lib failures are the same 24 as master.

Timing, body edit in a directive-free leaf file (same machine state, seconds from request start):
`frontend` stage mark 3.0 to 2.4-2.5 (the plan is ready at 1.4-1.5, the clone of the previous plan
and the 5.9k provider touches are about 0.4 of that); client wall 7.2 to 6.1-6.3.

Default flipped to on (2026-10-18, lane `tools/dmb-decl-patch`): `verify` on the production tree over a
body edit, a line-shifting comment, a two-file edit, a new var and a new proc in a leaf file, a revert and
three lane-alternating body edits logged 8 "plan edit equals the full plan" and 8 "expansion edit equals
the full expansion" and no mismatch; edits outside F1's preconditions logged "plan full". The patched
outputs were byte-identical to the full path. `DMB_FRONTEND_REVISION=0` turns it off.

Earlier note: the default stayed off until the other passes (declaration parsing, origins, bodies) take
the same edit and the whole edit matrix has been verified. The previous plan is cloned
(about 200 MB of region lines) because `DirectivePlan` is a plain value; sharing the regions behind
an `Arc` would remove the clone and the touches' only other cost.

## Retained session memory (lane `tools/dmb-session-memory`, 2026-10-17)

Goal: at most 2 GB retained per project session and a much lower compile peak, so three sessions fit in
8 GB. This section is the measurement; the cuts and their effect are appended below as each lands.

### How to measure

* **Live bytes by allocation call site (new).** Build with `--features allocation-sites` (a separate
  `CARGO_TARGET_DIR`), run the daemon with `DMB_ALLOC_SITES_PATH=<file>`. After every request the
  daemon writes `retained.after_request` (process private bytes, mimalloc commit, requested-live bytes) and the top
  400 allocation sites by sampled live bytes (one sample per 2 MiB requested, size-weighted). The counting build
  is slower (a cold production compile took 287 s instead of 130 s) but the retained set is the same.
* **Per-stage owner census (existing).** `DMB_HEAP_CENSUS_PATH` writes one JSON report per pipeline stage
  (`frontend.ready` ... `publication.ready`), `DMB_IDLE_CENSUS_PATH` one per idle-release boundary. Each report
  counts only the owners that stage visits, so it covers 1 to 1.8 GiB where the process holds about 9 GB:
  it does not see the observation/receipt store (below), which is the largest owner.
* `dmbc --daemon-stats`, `E:/dq-cache/dmb-daemon/lifecycle.log` (shared by all namespaces) for peaks and release tiers.

### Baseline (production `deepquarry.dme`, one native cold compile, 4 workers)

| Quantity | Bytes |
|---|---|
| compile peak (`peak=` in the lifecycle log) | 12.2 GB (13.0 to 13.2 GB for `deepquarry.test.dme`) |
| private after the request and `mi_collect` | 8.97 GB (11.95 GB before the reclaim) |
| requested-live (counting build) | 7.43 GB |
| mimalloc commit | 9.17 GB, so 1.74 GB (19%) is allocator slack (freed pages, thread heaps of finished workers) |
| private right after a `tier=session` release | 3.0 to 3.15 GB, but the daemon's next allocator reclaim (within 30 s) takes it to 1.13 GB with 0.18 GB live (counting build, DMB_ALLOC_SITES_RELEASE) |

Allocator findings (2026-10-17): after a build the daemon already joins idle workers and runs `mi_collect(true)`;
`private` then equals mimalloc's commit (9.07 GB) against 7.40 GB requested-live. The 1.7 GB difference is
size-class rounding and partly used pages pinned by long-lived small allocations, not freed pages, so purging more often
or with a zero purge delay returns nothing (a second forced collect from a fresh thread was also tried: 1.18 GB residual,
no change, reverted). Likewise the "3.1 GB with no session" is the transient between a session release and the next
reclaim; the steady no-session residual is 1.13 GB (0.18 GB live: shared engine, filesystem proofs, source checks). Vec and
hash-table slack in the census owners is 3 to 6 %. Remaining retained memory is data, not waste.

### What the retained set holds (sampled live bytes at idle, 7.28 GB sampled total, top 400 sites = 6.30 GB)

| Area | MB | Main owners (innermost frame) |
|---|---|---|
| observation and artifact store (`dm_session`) | 1,852 | `artifacts::incidence` 569 (scheduling index), `observations::receipt_pool` 389, `artifacts::leased` 387, `ObservedArtifactStore` 362, `observations::receipt` 139 |
| declaration parse, tree, owner metadata (`dm_tree`) | 1,355 | `declaration_parse` 232, `owner_metadata::RetainedMetadata` 181, `adapter::walk` 152, `owner_normalization::receipts` 79, `KeyedDeclarations` 63 |
| preprocessor | 1,093 | `region_memo` 286, `directives` 244, `directive_memo` 154, `expansion` 80, `prepared_source` 59 |
| lowering memo and symbolic code | 602 | `lowering::memo` 119, `symbolic_input` 79, `SymbolicCode` 70 |
| class projection, ABI, startup, other `dmbc` | 494 | `class_projection` 118, `driver_facts::abi_artifacts` 48 |
| initializer policy and classification | 284 | `classification` 184, `modifier_facts` 90 |
| DMB image and composition | 274 | `dmb::writing` 152 |
| unattributed (only std/hashbrown frames in the 5 shown) | 344 | |

The census structures the design names (expanded text 52 MiB, origin arena 40 MiB, source text 65 MiB, directive plan
135 MiB, declaration AST 91 MiB, body arena 99 MiB) are small. The retained cost is dominated by per-unit
observation receipts and per-region memos keyed by 87,000 procedures and 5,900 files, not by one big text.

### Cost of releasing retained state (2026-10-17)

Measured with the counting build (about 2.6x slower patches than the plain build: 14.3 s hot here against 5.4 s plain),
one daemon per row, full uncached compile, idle ladder applied to the idle session
(`DMB_ALLOC_SITES_RELEASE=<tier>`, diagnostic, feature `allocation-sites`), then a body edit:

| Released up to | Private after | Next edit | The edit after that |
|---|---|---|---|
| nothing (hot) | 9.05 GB | patch 14.5 s | patch 14.2 s |
| tier 2 (rich buffers) | 8.52 GB | patch 28.1 s | patch 11.7 s |
| tier 3 (compiler artifacts) | 7.27 GB | full compile 108 s | patch 15.1 s |
| tier 4 (optional images) | 6.91 GB | full compile 80 s | patch 14.4 s |
| tier 5 (compact symbolic) | 5.85 GB | full compile 99 s | patch 13.0 s |
| tier 6 (remaining optional) | 5.50 GB | full compile 74 s | patch 13.5 s |
| tier 7 (whole session, plain build) | about 1.1 GB | full compile 169 s counting | patch 12.8 s |

Findings: the disk memos make a released edit a 74 to 108 s compile (against 120 to 130 s cold), not a few seconds,
because a released session leaves no patch base ("patch declined: no patch base retained"). Every tier from 3 up costs the
next edit a full compile, so shortening the idle release (or the 30-minute MRU shield) would trade a full compile per
returning edit for the memory. The 1.85 GB observation store is part of what tier 3 drops: evicting it means relowering
(45 s in the released run), so it is not a cheap lazy rebuild. Revisit when record hits leave a patch base (lane
`tools/dmb-real-world`): a released edit could then patch from persisted records.

## Daemon lifecycle and the adaptive memory budget (lane `tools/dmb-retain`, 2026-10-17)

Measured on the real stats file (`E:/dq-cache/dmb-daemon/compile-stats.jsonl`, 352 compiles over one working day, 5 lanes plus a
play server): 40% of compiles took the hit or patch path, session hit rate 9.1%. Causes of the other 60%:

| Cause | Evidence | Fix |
|---|---|---|
| Session key held the engine template **path**, and every worktree has its own `native_template.bin` | `variant-mismatch` (24); two resident sessions of one variant pushed the daemon past the fixed 8 GB hard limit (`evicted:hard-memory-limit`, 44) | key by the template's content hash (`EngineIdentity`) |
| Daemons replaced each other: a client of another image retired the discovery holder, a starting daemon retired the least recently used idle peer (the one with the hot sessions), namespaced test daemons and an unregistered busy daemon (`dmb-build-rw`) used up the cap of 2 | 112 daemon starts for 352 compiles; 133 compiles ran on a daemon with under 300 MB private, i.e. freshly started (`no-session`, 184) | no newcomer-retires-incumbent at all (below) |
| Fixed 8 GB budget against a 10 GB session | after every full compile private was 10 to 11 GB, so every other session was shed while 14 GB of RAM was free | budget follows available physical memory (below) |
| No patch base after a hit-only session | `no-patch-base` (63): cheap (3 to 6 s record hits), not a full compile | unchanged |

### Who owns which daemon

* The endpoint is keyed by the compiler image identity, so a client only ever talks to the daemon of its own version, and starts
  one when none exists. Nobody retires another version's daemon: `retire_discovered`, `enforce_cap` and `DQ_DMBC_MAX_DAEMONS`
  on the daemon side are gone.
* A **development build** (any `dmbc` not under `<bin>/v/<id>/` with `<id>` named by `<bin>/current`, so a worktree `target/`, an
  explicit `DQ_DMBC_BIN`, a test fixture) sets `DMB_DAEMON_NAMESPACE=dev-<image id prefix>` itself at startup
  (`resident::isolate_development_build`): its daemon, discovery endpoint and sessions are private and it never touches the
  published daemon. An explicit `DMB_DAEMON_NAMESPACE` still wins.
* A daemon leaves for idleness (`DMB_DAEMON_IDLE_EXIT_SECS`, default 1 hour), for memory (below), on `--daemon-retire`, or, as a
  **superseded published version** (`<bin>/current` names another id), once it has had no connection or build for 30 minutes. Which version a checkout runs is chosen by its own compiler sources
  (`<bin>/by-key/<cache key>`, or `<bin>/by-tree/<hash>` for a dirty compiler tree), never by whoever built last; `<bin>/current` is only
  the default for a checkout that has not built, and a publish moves it only forward along history (`<bin>/current.commit`).
* The caller-namespace registry in `tools/build/lib/dmbc_daemons.ts` keeps its count cap for explicit namespaces (bench,
  experiments) but never retires a namespace used in the last 10 minutes.

### Adaptive memory budget

Unless `DMB_DAEMON_SOFT_PRIVATE_BYTES`, `DMB_DAEMON_HARD_PRIVATE_BYTES`, `DMB_DAEMON_MEMORY_BUDGET_GB` or
`DMB_DAEMON_ADAPTIVE=0` is set, pressure follows the machine (`soft_memory.rs`): hard when available physical memory is under the
reserve (`DMB_DAEMON_FREE_RESERVE_GB`, default 8), soft under reserve + 4 GB, emergency (the newest session loses its 30 minute
shield) under half the reserve. A compile is admitted only while available memory covers the growth the last build of that
project and kind (hot or cold) caused (default 2 GB hot, 12 GB cold) on top of the reserve: `Shared::await_memory` releases idle
sessions of other projects least recently used first, then waits for running builds, and with nothing left to release or after 5
minutes admits the build and logs the shortfall (a machine that is too small slows down instead of refusing every build).

## Daemon-wide retained budget and superseded-daemon reaper (lane `tools/dmb-session-memory`, 2026-10-17)

Measured on the live daemon's logs (`E:/dq-cache/dmb-daemon/compile-stats.jsonl`, `lifecycle.log`, pid 9292, 8 lanes): the shared
compile roots work, two sessions (`deepquarry.dme`, `deepquarry.test.dme`) serve every worktree. 330 compiles went through
them; 137 were hit or patch (4% of compile time) and 193 full (96%). Full-compile causes: new daemon version after a publish 86
(`no-session`), old fixed cap 52, old path keying 22, other eviction 16, cross-tree declaration change in a hot session 17 (mean
88 s, peak 22 GB with two sessions because the old state lives through the rebuild).

* **Budget.** `DMB_DAEMON_MEMORY_BUDGET_GB` (default 20 for now, so production and test sessions stay resident; lower it as sessions shrink) is the daemon-wide retained budget on top of the machine-pressure policy:
  over it, `Shared::enforce_retained_budget` releases the least recently used idle session whole, after every build and before a
  build is admitted (against its expected growth). The newest session and any building session are never released, so a lone
  session larger than the budget stays resident. Policy: `soft_memory::budget_victim` (tests in `soft_memory.rs`).
* **Superseded daemons.** The 12:40 daemon (version `ebfc6fb0e7c801a8`) was last active 16:43, heartbeating, not busy: its binary
  predates the superseded-version exit and only had the 1 hour idle exit, and a newer daemon never retired older ones. A daemon
  of the current published version now asks every registered, live, not busy peer of another published version in the same `<bin>`
  that has been idle for 2 minutes to retire, through the `<pid>.retire` flag every registry-aware build honors in its heartbeat
  (`resident::retire_superseded_peers`, checked every 30 s; test `current_daemon_asks_only_idle_live_superseded_peers...`).
* Baseline (plain release build, 4 workers, machine busy): cold production compile 159.5 s, peak 9.33 GB, private after 9.03 GB.

### Admission respects the budget (2026-10-17)

With the 20 GB budget landed the daemon still released an idle session at admission ("available 10.0 GB, build needs 10.3 GB above
a 8.0 GB reserve"): the estimate is a full compile's growth, charged even for a build that will patch. Admission now releases an
idle session only for a real shortage (available memory under the reserve, default lowered 8 to 4 GB) or when the daemon would pass
its budget with the build (`soft_memory::admission_may_shed`); the retained budget itself is enforced separately and releases the
least recently used idle session.

### One session per project, one state per variant (2026-10-17)

`SessionKey` is the project directory plus compiler (engine bytes, bootstrap), not a manifest file and not a define set. The
compile root is one per project (`rootKey`: `deepquarry`, `deepquarry.test`, `deepquarry.bench` share it). `BuildHost::engine`
no longer discards everything when only the project path or defines change: `switch_variant` stashes the define-dependent state of
the variant it leaves (procedure memo, semantic tree, ABI, startup, initializers, class projections, link bindings, the retained
generation that is the patch base, resources, maps, symbolic memo) under its configuration and restores it when that variant is
built again; the engine payload, executors, shared procedure code and the directive/expansion/fragment memo are shared. At most 3
variants are stashed, they go first when the session degrades (tier 3), and a query for a variant that is not the active one says so.
This is the interim shape of "the session is the query database and the defines are inputs" (`incremental_core.md`): when the `Db`
lands the stash becomes per-query reddening and the patch base a persisted dependency index.

### Stashed variants go first under pressure; the compiler is published again (2026-10-17)

Measured after the variant stash landed: one session holding production and test is 16 GB private (production 9 GB, the stashed
test variant about 7 GB). Under pressure housekeeping now drops the stashed variants (`tier=stashed-variants` in the lifecycle log)
before it degrades or releases the variant the session serves. A worktree switch is not a variant: every checkout syncs into the
one compile root per project, so the switch is a changed input set of the same session (patch, or a stored-record hit when it
returns to a tree already built), and nothing is discarded for it. Separately, `build.sh dmbc` had stopped publishing: its Juke
target compared source mtimes against `dmb-bin/current`, which every checkout's publish rewrites, so after a cache miss the target
was "up to date" and `current` stayed on an old compiler (23d9d283) while newer dmbc changes landed; the target now decides by the
source content key alone.

## Shared store: one in-memory copy of every immutable value (lane `compiler/shared-store`, 2026-10-25)

Sharing used to exist only on disk (the content-addressed dm-cache, shared by every worktree). In memory each retained session (one per
compile root, and the test variant inside a session) decoded and owned a private copy of everything. The machine already ran one daemon
(`tools/build/lib/dmbc_daemons.ts` has had no per-worktree namespace since `96f987daf0`; only a development build or an explicit
`DMB_DAEMON_NAMESPACE` gets its own), so the duplication was between sessions inside one daemon, not between daemons.

### Measurement

`DMB_MEM_MARKS=1` (stage marks, see "Memory diet" below) also logs, in a daemon, what the shared store holds after every request, next
to the allocation-sites report. Tools: `bench/shared_store_probe.sh` (one private daemon, roots compiled in order, retention policies that never
shed a session, one `retained.after_request` block per request), `bench/alloc_sites_by_owner.py` (owner summary, `--diff A B` for growth),
`bench/shared_store_equiv.sh` (equivalence), `bench/shared_store_bisect.sh` (which owner changed an output). Counting build, production
`deepquarry.dme`, 4 workers, root A and root B two copies of the tree differing by a few comment lines (so what B adds is, to within those
lines, byte-identical to what A already holds), then the test world (`-DCBT -DCIBUILDING -DCITESTING -DDEBUG`) of root A:

| One daemon, requested-live (private), peak, wall | Before (`999733b646`) | After |
|---|---|---|
| root A, production | 7.17 GB (8.97), peak 10.9 GB, 179 s | 7.19 GB (8.93), peak 10.9 GB, 143 s |
| + test variant of root A | +5.02 GB (15.09), peak 17.2 GB, 187 s | +4.82 GB (14.78), peak 16.7 GB, 129 s |
| + root B, production | +4.63 GB (20.59), peak 22.6 GB, 103 s | +2.89 GB (18.11), peak 20.0 GB, 67 s |

The target of at most 1 GB per extra session is not met: a second root now costs 2.9 GB instead of 4.6 GB and the test variant is nearly
unchanged. What B added before, by owner (MB): preprocessor memo records 750 (`region_memo` 471, `directive_memo` 279), artifact stores
(`leased`, `ObservedArtifactStore`, receipts) 580, initializer classification 221, lowering records and artifacts 220, PublicationStore 126,
portable meanings 134, directives 124, link relocations 103. After: the memo records are gone, classification and the lowering records are
claimed, not copied; what B still adds is per-session machinery (below).

### Design as built (`dmbc/src/shared_store.rs`)

One `SharedStore` lives in the daemon (`Shared`); `activate()` makes it the process store at daemon start, and unit tests and one-shot
compiles never activate it, so their owners stay private. It holds:

* **Memo records** (`SharedRecords`, was the per-session `ResidentMemo` store): decoded expansion, directive and fragment records, keyed by
  content, one byte budget for the daemon (the old 8 GB cap). A session's `ResidentMemo` keeps only its own expansion admissions; releasing a
  session clears the records only when it is the last holder.
* **Artifact cores**: the `ObservedArtifactStore` behind each `PublicationStore::shared_current_revision(name)` (class projection owners and
  types, header recipes, initializer classification, modifier facts, fragments, assemblies, startup artifacts, required types, type
  creation order) and the class-projection and lowering-record stores. Each session keeps its own `ObservedArtifactLease` on the core (its
  claim roster); a variant lives while any session's lease claims it, so the last session to release frees it. A shared variant is found
  by exact key and validated against the asking session's own reads and local inputs exactly as a candidate read from disk is, so sharing
  changes memory, never output. `with_limit(bytes)` owners (explicit aggregate budget) stay private.
* **Receipt pools** (`receipt_pool(name)`): classification and ABI intern equal read groups daemon-wide (lowering already did).
* **Per-leaf proof lists** (`query_db::LeafProofs`): the derived (query id, query, answer hash) list of a unit proof is computed once per
  interned read leaf instead of once per unit and session (about 190 MB per session before).
* `DMB_SHARED_STORE=0` keeps everything private, `DMB_SHARED_STORE_PRIVATE=name,name` keeps named owners private (`records`, `pools`,
  `proofs`, core name prefixes), `DMB_MEM_MARKS=1` logs the store.
* **Facts policy**: `ProcedureMemo::facts_policy` is the memo policy without the `DEBUG` byte, used by initializer classification and
  modifier facts (which hold facts, not generated code) so the game and test variants claim the same artifacts. Code-holding caches keep the
  full policy.
* The default pair store moves from the drive root (`E:\.dmbd\pairs`) to `E:\dq-cache\dmbd\pairs`; the first compile moves an existing one
  (`publish::migrate_store`), and the age sweep still covers the old location.

Rule for sharing an owner: its key must name everything the value depends on (policy, build flags), because a shared core is read by sessions
and variants whose per-variant stores used to keep unequal keys apart. Two owners broke that rule and were caught by the equivalence run, not
by dmb-equiv: the lowered modified-instance initializer code carries DbgFile/DbgLine ops only when `DEBUG` is defined and its binding key did
not say so (the test variant claimed the game variant's op-free code; 93 initializer procs lost their debug ops, bytes differed by 1,488 and
`dmb-equiv` called it EQUIVALENT because it does not compare those ops). `Binding::modified` now carries the flag; fragment and assembly
bindings carry the policy in their key.

### Equivalence

`bench/shared_store_equiv.sh` compiles every (root, flavour) cold in its own daemon with sharing off, then the same list through ONE daemon
with sharing on, interleaved (A game, B game, A test, B test, B game, A game), each phase with its own pair store so no stored record answers
the shared run. Required per output: the reference pair id, byte identity of `.dmb` and `.rsc`, `dmb-equiv --all --ignore-debug`
EQUIVALENT, and the other root's marker proc absent (each root carries `MARKER-A`/`MARKER-B`, read back with `dmb-equiv dump-proc`). Result,
final tree: all six outputs byte-identical to their cold references for both worlds (production and `-DCBT -DCIBUILDING -DCITESTING
-DDEBUG`), no marker leak. In-tree test: `shared_store_tests.rs` (child process with the store active, fresh oracles with sharing off,
alternating edits of two roots); `leases_of_two_sessions_share_one_variant` pins the lease semantics. `cargo test` of dmbc, dm-session,
dm-query and dm-preprocess pass.

### What is left, by size

Per-session owners that still duplicate content-identical data (B's growth after this change, MB): answer table `RequestAnswers` 338 (one
144-byte slot per answered query, about 1.6 million per session), lowering record shells `symbolic_input` 146 plus their stores 178 (each
session rebinds a claimed record with its own local certificate and key), directive plans 127, classification receipts 113, domain version
memo 85, retained image `codec` 75, link relocations 100 (production) to 300 (test), joined text and prepared sources 120. The test variant
cannot share its lowered code with the game variant while `DEBUG` selects whether debug ops are emitted during lowering: the lowering policy
carries the flag, so all 93,000 bodies are recomputed and stored twice. Emitting the ops always and stripping them at link time for builds
without `DEBUG` would make lowering records variant-independent (the strip is a removal of opcode 0x84/0x85 instructions; emission of other
instructions does not depend on them), and is the largest remaining owner for the test variant. Sharing the answer table needs the
bookkeeping (`request`, `born`, `changed`, `base`) split from the content-defined value (`hash`, `positive`, `query`) of a slot.

### Shared store, part 2 (lane `compiler/shared-store-2`, 2026-10-25)

Target of the user: each extra session (a second root, the test variant) at most about 1 GB. Measured with `bench/shared_store_probe.sh`
(requested-live of one private daemon; root A production, then A's test world, then root B production), release build with
`allocation-sites`, fresh output store per request, no spill files of an earlier run (`DMB_VARIANT_SPILL=0` or a new compiler build). One
probe differs from another by about 0.15 GB without any change of code, so only larger moves are real.

| Step | root A | + test variant | + root B |
|---|---|---|---|
| part 1 (above) | 7.19 | +4.82 | +2.89 |
| 1. variant-independent lowering | 7.21 | +4.69 | +3.20 |
| 2. answer values shared, slots compacted (32 B) | 7.13 | +4.07 | +2.75 |
| 2b. rebound records keep predecessor debug anchors and domain receipts | 7.33 | +4.07 | +2.73 |

* **Lowering is variant-independent.** `FrontendDebugProvider` always emits `DbgFile`/`DbgLine`; the lowering record keys use
  `ProcedureMemo::facts_policy` (the policy without the `DEBUG` byte). A source without `DEBUG` drops the two instructions from its final
  words in `LatestImage::wire_image` (`symbolic/debug_strip.rs`: the removed words are compacted out and every branch destination,
  switch case and pick target is shifted; a destination naming a removed instruction names the next kept one). The words are stripped
  after type-path wiring and never cached stripped, and the certificate's `debug` feature is cleared (`BytecodeFeatures::composed_under`),
  so the header flag matches. `LinkTables::strips_debug_ops` (set from `LinkInventory::strip_debug_ops`, restored with the spilled patch
  base, `variant_spill` version 2) carries the choice to every relink, including body patches. Initializer, map and modified-instance
  lowering still decide on `DEBUG` themselves and still key on the full policy.
* **Answer table.** A slot is `{value: Arc<AnswerValue>, base: Option<Arc<AnswerValue>>, request, born, changed, stamp}` (32 B, was 144 B);
  the value (query, answer hash, positive) is interned daemon-wide by query id (`shared_store::answer_values`), the (tree, world) pair is
  an index into the request's stamp list, request numbers are the low 32 bits.
* **Not shared (tried).** Interning each body's origin roster by content (`FrozenDebugOrigins`) removed nothing from the probe and was
  dropped.

What is left per extra session, by owner (MB, root B after part 2): `leased` roster/bookkeeping 160 to 440, the symbolic record rebinding
in `SessionSymbolicMemo::lookup_record` 150 (allocated inline; the profile cannot split it further, inlining hides the callees), preprocessor
directive plan 137 (`DirectivePass::visit`, per source line), initializer classification 119, `ObservedArtifactStore` 82 to 110, ABI
artifacts 81 plus `CapturedProcedurePolicy` 58, `RequestAnswers` 67 to 80, `OutputBase` 145, `dmb::codec` 75, input snapshot reads 69,
prepared source and joined text 120, domain-version memo 56, `RetainedMetadata` 59. None of these is one allocation that can be removed:
each is a per-session index over shared content, so reaching 1 GB needs those indexes themselves to become shared (a design change of the
retained directive plan, the artifact leases and the ABI/initializer receipts), not another interning pass.

Tools: `bench/alloc_sites_diff.py` (growth by call path between two probe blocks; run the probe with the exe in `target/release` so the
frames are symbolised). `bench/shared_store_equiv.sh` now fails on a byte difference (it only noted one before) and takes `BASE_DIR`, the
outputs of an earlier compiler build of root A, as a second oracle.

### Shared store, part 3 (lane `compiler/shared-store-3`, 2026-10-25)

Target of the user unchanged: at most about 1 GB per extra session (second worktree root, test variant). The method of part 2
(per-session indexes over shared content must themselves be shared, a session keeping only what differs) was applied to every owner whose
content is a pure function of shared content; measured with `bench/shared_store_probe.sh` on the allocation-sites release build (requested
live, GB; root A production, then the A test world `-DCBT -DCIBUILDING -DCITESTING -DDEBUG`, then root B production; root B is a copy of
A with a comment line in two files), the oracle of every step being `bench/shared_store_equiv.sh` with `BASE_DIR` set to the outputs of
the build before this lane (byte identical `.dmb` and `.rsc`, pair ids, both worlds, interleaved roots, no marker leak). One probe differs
from another by about 0.05 GB on its own.

| Step | root A | + test variant | + root B | sum |
|---|---|---|---|---|
| part 2 tip (`e14bb82ba4`) | 7.10 | +3.96 | +2.69 | 13.75 |
| 1. lease rosters are one bit per claim | 6.85 | +3.77 | +2.50 | 13.13 |
| 2. prepared sources and modifier locators shared by content | 6.87 | +3.68 | +2.25 | 12.80 |
| 3. segment lines are runs over the prepared source | 6.78 | +3.56 | +2.16 | 12.50 |
| 4. leaf proofs 32 B; procedure word pools | 6.78 | +3.52 | +2.10 | 12.40 |
| 5. (master merged, new tree) owner storage facts and expansion inputs shared | 6.81 | +3.48 | +1.99 | 12.28 |

The target is not met: a second root now costs about 2.0 GB and the test variant about 3.5 GB. Step 5 was measured on a tree that
master had changed (354 files), so its row is not comparable with step 4's; its own effect on root B is about -0.1 GB.

* **Lease rosters (`dm-session/src/artifacts/leased.rs`).** The per-lease `BTreeMap<key, pointer>`, the global claim index
  `BTreeMap<pointer, (hash, count)>` and the deferred claim list are gone. Each `Variant` carries `Holders`, the set of lease slots
  (128 per core, two atomic words) claiming it; a lease's roster is the variants naming its slot, at most one per exact key. A claim of a
  stored variant is `fetch_or` of one bit under the read lock (no deferral, nothing pending); a claim that replaces another variant of
  the same key takes the write lock and frees the replaced variant when no other lease holds it. A lease drop or `retain_*` walks the
  buckets once. Cost per variant: 16 bytes whatever the number of sessions, so a session whose claims equal the base costs one bit per
  claim. The pressure model no longer charges a roster entry per claim (a claim adds no index bytes); three pressure tests that asserted
  claim growth changing the charge now assert it does not.
* **Prepared sources (`prepared_source::shared_prepared`).** Lexical preparation is a pure function of the decoded text, so every
  producer (capture workers, the directive pass fallback, the native input scan, the prepared input store) goes through a weak
  process-wide pool keyed by the text digest and verified by the text: the text, its comment-stripped view and the line tables exist once
  per distinct file. Modifier locators (`shared_locator`) are pooled the same way by their key bytes: each write keeps one key and one
  input allocation across sessions.
* **Segment lines (`dm-preprocess/src/regions/segment_lines.rs`).** An `ExpansionSegment` held a copy of every active logical line (56
  bytes each, 1.7 million lines per plan, held again by every session and variant). It now holds the shared `PreparedSource` and the runs
  of line indexes it took (conditional directives break a run); iteration yields `PreparedLineView`s. `expansion.rs`, `region_memo.rs`
  and the directive plan comparison read views instead of `&RegionLine`.
* **Procedure words (`symbolic/image_pool.rs`, `debug_strip.rs`).** Linked and wired words are interned by content in a daemon-only
  weak pool (`shared_store::active()` gates it; one-shot compiles and unit tests keep private words), which also makes the wire cache of
  a shared artifact, keyed on the identity of its base words, hit across sessions. A shared image stripped of its debug ops for a build
  without `DEBUG` is stripped once (by image address) instead of once per session.
* **Leaf proofs.** A derived entry no longer carries the query it already holds in its leaf: 64 to 32 bytes per read.
* **Owner storage facts and expansion inputs.** `RetainedStorage` keeps the per-owner facts in a lease on a core of
  `SharedNormalizedDeclarations` (the engine-scoped owner dm-tree already shares its normalized rows through); the uniqueness
  certificates stay private because their tokens are issued by the process for one tree. `ExpansionInputs` leases a core that
  `shared_store::activate` creates through `dm_preprocess::regions::share_expansion_inputs()` (`DMB_SHARED_STORE_PRIVATE=expansion`
  keeps it private); every hit is still replayed against the asking plan.

What was looked at and not done, with the growth of root B it would address (MB, step 4 probe):

* **Domain version tokens.** The `versions` list of every rebound lowering record (124, the largest remaining site, in
  `SessionSymbolicMemo::lookup_record`: 64 bytes per read domain), the domain memo (55), `RetainedMetadata` name demand (62) and
  `MetadataDependencies` (59) hold tokens issued by process-wide counters (`NEXT.fetch_update` in `owner_metadata`, `storage_uniqueness`,
  `procedure_static_layout`, `constant_resolution_artifacts`), so two sessions with identical declarations get different tokens and a rebound
  record cannot reuse its predecessor's list. Issuing tokens as a digest of what they certify (as `query_db` answers already are) would
  make them equal across sessions and let all four owners share; it changes the meaning of every certificate and needs its own design.
  A `(domain, token)` list stored as a shared domain list plus a token array would save about 75 percent of the 124 but touches 470 sites.
* **Whole-project vectors of the preprocessor** (plan items and regions 119, joined text 60, origin arena 44, macro environments 39, region
  outputs 54): single allocations per plan, so two plans of nearly equal trees share nothing unless they are chunked per file. The
  joined text is one `Emission` equality away from reuse only for identical trees.
* **Output buffers** (`dmb::codec` 75, word lists 36): the retained encoded output of each session.
* **ABI units hydrated from disk** (109): built from the session's own metadata.

Tools: `bench/shared_store_probe.sh` and `bench/alloc_sites_diff.py` as before. Reading an allocation site: the report names the
innermost frame with a line number; an inlined callee shows as its caller (`lookup_record` held the `versions` conversion), so the line
number, not the function, names the site.

### Shared store, part 4 (lane `compiler/shared-store-5`, 2026-10-26)

Target of the user unchanged: about 1 GB per extra session. Master gained content-digest domain-version tokens (`b584bac20a`) and
content-shared retained output images (`05fbeae28e`); this lane measured their effect and tried to cut the largest remaining owner.
Method of part 3: `bench/shared_store_probe.sh` on the `allocation-sites` release build (requested live, GB; root A production, the A
test world `-DCBT -DCIBUILDING -DCITESTING -DDEBUG`, root B a copy of A with a comment line in two files), 4 workers, fresh output store.
The machine was shared with another lane's test world and cargo build, so wall times are inflated and one probe differs from another
by about 0.05 GB.

| Step | root A | + test variant | + root B | sum |
|---|---|---|---|---|
| master `8e5a8be879` (digest tokens, shared images) | 6.81 | +3.47 | +1.93 | 12.22 |
| content-digest provider issuers (not landed) | 6.83 | +3.45 | +1.90 | 12.18 |

**The two earlier changes took almost nothing off the totals.** Part 3 ended at about 2.0 GB for a second root and 3.5 GB for the test
variant; they are now 1.9 and 3.45. The shared output image only helps two sessions that publish equal outputs (a second worktree at
the same commit); the test variant publishes a different image, and `dmb::codec` is still the largest test-variant owner.

**Tried and not landed: provider issuers as content digests.** The callable and variable engine providers
(`engine_host/engine_providers.rs`) draw their `issuer` from a process-wide counter at every capture, and every catalog,
variable-negative and callable version token is `compose_version(base, issuer)`. Two sessions capturing equal engines therefore hold
unequal tokens even though the tree tokens under them are digests, so a rebound lowering record cannot keep its predecessor's
`versions` list. The lane made the issuer `xxh3(tag, engine identity, payload)` masked to 56 bits (`variable_negative::qualified`
multiplies it by 4 with checked arithmetic; 64 bits made it decline every token and failed two tests). Effect on root B: the rebinding
site `SessionSymbolicMemo::lookup_record` fell from 144 to about 110 MB; the sum did not move. **It made the warm patch rebuild slower:**
three interleaved rounds of three one-line edits to `code/game/world.dm` in root A (`--workers 4`, own daemon per build, allocation-sites
release builds) gave master 8.83 to 10.32 s (mean 9.47) and the digest-issuer build 10.93 to 12.83 s (mean 11.71), 24 percent slower,
far over the 5 percent limit. The outputs were correct (`shared_store_equiv.sh` with `BASE_DIR`: game and test `.dmb`/`.rsc` byte-identical
to the pre-change build, all six interleaved shared-daemon builds byte-identical and `dmb-equiv` EQUIVALENT), so the cost is work, not
a wrong answer: the likely cause is that equal issuers across captures let rebound records and version checks take a slower validating
path where unequal tokens used to fail fast, which was not profiled. The code is not landed; its diff is kept at
`E:/dq-cache/shared-store-5/issuer-digest.patch` (with the `lowering_policies` refactor and its two tests). Sharing anything built on
those tokens (domain memo, name-demand receipts, `MetadataDependencies`) still needs stable issuers, and first a profile of that patch
rebuild.

**Tried and removed: a daemon-wide pool of `versions` lists.** Interning each rebound record's `(domain, token)` list by content did not
measurably move root B (6.83 / +3.51 / +1.94 with it), and the warm patch rebuild of the pooled build was 10.1 to 12.1 s against
9.3 to 10.4 s, so it did not land.

### What is left, in order, with a design for each

The target is **not met**: a second root costs about 1.9 GB and the test variant about 3.45 GB. Next owners (growth, MB):

| Rank | Owner | Second root | Test variant |
|---|---|---|---|
| 1 | `driver_facts::abi_artifacts` | 97 | |
| 2 | `query_db::RequestAnswers` | 77 | |
| 3 | `initializer_policy::classification` | 75 | |
| 1 (test) | `dmb::codec` output buffers | | 196 |
| 2 (test) | `dm_session::artifacts::leased` | | 174 |
| 3 (test) | `query_db::AnswerValues` | | 133 |

* **`abi_artifacts` (97).** The ABI units are hydrated from the disk cache (`UnitWire::hydrate_current`) into a per-session store keyed
  by the session's own metadata. Design: make a hydrated unit a function of its wire bytes, which are already content addressed in
  `dm-cache`, and intern the decoded unit in a weak daemon pool keyed by the record digest; the session store keeps `Arc`s plus its own
  receipt and certificate. It is per-session today because the unit embeds the session's metadata tokens and local certificate inline
  instead of beside the shared payload; splitting those two out is the change.
* **`RequestAnswers` (77).** Part 2 already moved the content-defined value out; what remains is the 32-byte slot (request, born,
  changed, stamp, two `Arc`s) per answered query, about 1.6 million per session. Design: store runs. Answers of one request that share
  `born` and `changed` are contiguous in query-id order, so a session keeps a sorted `(first id, bookkeeping)` run list and a bit per
  query for presence, about 1 to 2 bytes per answer. It is per-session because the bookkeeping names this session's requests, so it can
  be compacted but not shared.
* **`classification` (75).** Initializer classification receipts are claimed from a shared core but each session rebuilds the per-unit
  receipt group around its own tree tokens. Design: with digest tokens and digest issuers a unit's receipt group is a pure function of
  the unit's reads, so intern it in the existing `receipt_pool("classification")` by content and let the session hold only the unit
  index. It is per-session today because tokens differed between sessions until these changes; the groups are now equal and need to be
  looked up by content instead of rebuilt.
* **`dmb::codec` output buffers (196, test variant).** The test world publishes its own image, so whole-image interning
  (`output_pool`) cannot help. Design: chunk the retained encoded image at stable section boundaries (string table, procedure bodies,
  type tables) and intern each chunk by digest, so the game and test images share the procedure bodies that are equal after debug-op
  stripping. It is per-session because the writer produces one contiguous `Vec<u8>` per output, which only matches another output when
  every byte matches.
* **`leased` (174, test variant).** One bit per claim (part 3) is paid for every variant a lease claims; the test variant claims about as
  many as the game variant over mostly the same variants. Design: let a variant session lease the game session's roster as a base and
  keep only a delta (claims added, claims dropped), so a session whose claims equal the base costs nothing. It is per-session because a
  lease is the claim roster of one session; the delta form is the missing piece.
* **`AnswerValues` (133, test variant).** The interned answer values are keyed by query id; the test variant adds values because its
  answers differ in the debug-dependent domains. Design: intern by `(query, answer hash)` and keep one allocation per distinct answer
  independent of query id, since many ids carry the same positive answer. It is per-session only in that the intern key includes the id.

**What reaching 1 GB would take.** Root B needs about 0.9 GB removed. The three designs above are about 250 MB together; the rest is
the long tail of per-tree indexes (`joined_text` 61, `RetainedMetadata` 64, `MetadataDependencies` 59, `frame_contribution` 54,
`domain_memo`, `region_memo`, the preprocessor's whole-project vectors), each a cache of a pure function of the tree. Those need a
tree-state identity to key a whole-cache share on (two trees equal up to a comment would share a cache, not copy it) or per-file chunking
of the preprocessor plan; that is a design change of its own, not another interning pass, and is the realistic route to 1 GB. The test
variant needs the chunked image and the roster delta first (about 370 MB), and its remaining 3 GB is mostly code that differs by `DEBUG`
(initializers, maps, modified instances), which only a debug-independent lowering of those three kinds would share. These estimates are
sketches, not measurements.

## Memory diet (lane `compiler/memory-diet`, 2026-10-24)

Question from the user: why does the compiler keep the whole source in memory? Measured answer: it does not. One production
compile has about 65 MB of source text; the retained set is derived data keyed by 87,000 procedures (observation receipts, memos,
decoded records). The measurements below are for the plain release build, 4 workers, an isolated warm disk cache
(`DMB_CACHE_DIR`), `deepquarry.dme`, byte-identical output (pair `663ace59970f1694972a1dfcd6eb9fe6`; the `-DCIBUILDING -DCITESTING`
world `ec9bf1cd6a29d642cf6eedc8f2a53c63`, both unchanged).

### How to measure one compile by stage (new)

`DMB_MEM_MARKS=1` prints `mem mark <stage>: live=<MB> peak=<MB> commit=<MB> private=<MB>` at every `request_mark` stage of a
one-shot or daemon build (`live` and `peak` need a build with `--features allocation-counting`). With `--features allocation-sites`,
`DMB_ALLOC_SITES_PATH=<file>` and `DMB_ALLOC_SITES_MARKS=<stage,stage|*>` also append the live-bytes-by-call-site report at those
stages, so a one-shot (`--no-daemon`) compile can be broken down without a daemon. Compare two stages by diffing the per-site lists.

### What the stage curve looks like (counting build, shared 36 GB disk cache)

| Stage | Live MB |
|---|---|
| frontend ready (plan, expansion, declarations, tree) | 2,505 |
| ABI waves | 2,905 (+500) |
| initializers done | 3,813 (+900) |
| lowered | 4,666 (+850) |
| sealed (peak) | 5,423 |
| frontend dropped | 4,389 |
| end of the one-shot compile | 3,940 |

### Cuts landed

| Holder | Before | After | Change |
|---|---|---|---|
| Disk-cache index per `Segment` (`BTreeMap<RecordKey, Entry>`, ~90 B per record) and per snapshot (`BTreeMap<RecordKey, Vec<usize>>`) | 575 MB at frontend (shared cache: 49 segments, 36 GB) | about 80 MB | `Segment` keeps a `Vec<u32>` of descriptor slots sorted by key and reads the descriptor (key, offset, length, checksum) from the mapping; the snapshot keeps two flat arrays (key hash, segment ordinal), 12 B per record, and confirms every hit against the segment. Index memory now scales at 16 B per cached record instead of ~160 B. |
| Decoded memo records (`ExpansionRecord`, `DirectiveRecord`) | every macro read, trace name, replacement chain and definition a fresh allocation per record | shared through `regions/intern_wire.rs` pools | Retained region and directive memo records fell from 1,044 MB to 554 MB in the sampled daemon session. Wire form and every comparison are unchanged (a freshly expanded record already shared the plan's `Arc`s). |
| `DomainMemo` entries | 40-byte domain enum key, ~80 B per entry | 128-bit digest key, 48 B per entry | estimated 100 MB of the 200 MB at peak (not measured separately) |

Result (same inputs, isolated warm cache, external private-bytes sampling for one-shot, `native compile:` log for the daemon):

| | before | after |
|---|---|---|
| one-shot compile peak private (warm 2.6 GB cache, 1 segment) | 4,717 / 4,699 MB | 4,480 / 4,460 MB |
| one-shot compile live peak, shared 36 GB cache (counting build, cache index change only) | 5,423 MB | 4,897 MB |
| daemon session after a full compile (private) | 8,330 MB (peak 8.34 GB) | 8,020 MB (peak 8.03 GB) |

### Where the rest is (retained daemon session, 7.0 GB live)

Observation store `leased` bookkeeping 830 MB (four `BTreeMap`s and a `Vec` per entry for about 2.5 million artifacts), receipt
groups 400 MB, receipts 320 MB, `RetainedMetadata` 300 MB, directive plan 285 MB (`RegionLine` is 56 bytes per source line),
resident memo records 550 MB, declaration parse payloads 226 MB, lowering memo 270 MB. The `control` byte string of every region and
directive interval holds a second copy of the comment-stripped line text (about 100 MB each): shrinking it changes the record
key, so it needs a record version bump. The resident record store (`runner_host_memo.rs`, 8 GB budget) keeps a decoded copy of every
record accepted from the mmapped disk cache; a smaller budget trades the decode on the next request for memory, so it needs a
measured edit-latency decision. A one-shot compile builds receipts for the name-demand store that nothing reads again.

### Memory diet 2 (lane `compiler/memory-diet-2`, 2026-10-25)

Plain release build, 4 workers, a fresh isolated `DMB_CACHE_DIR` per run (cold, forced full compile), `DMB_MEM_MARKS=1`. Output is
byte-identical (sha256 of `.dmb` and `.rsc`), the pair ids are unchanged, and `dmb-equiv --all --ignore-debug` reports EQUIVALENT
for both worlds.

| Measure | before | after |
|---|---|---|
| one-shot peak private, `deepquarry.dme` (pair `187541544b62ca3e0347da5da9c40350`) | 5,523 MB | 4,758 MB |
| one-shot peak private, `-DCIBUILDING -DCITESTING` (pair `4baef5b1e135e47d209d2b4b4637638b`) | 5,983 MB | 5,031 MB |
| daemon session private after a cold full compile | 7,712 MB | 7,453 MB |

- **One-shot compiles store no name-demand receipts.** `RetainedSemanticTree::one_shot()` (the request-local owner in
  `request_runner.rs`) builds a `RetainedMetadata` with `retain_receipts = false`: `demanded_name` and the member-name selector
  still issue and cache the token per tree, but skip the store lookup and insert. Daemon sessions keep the receipts.
- **Region and directive memo records keep a control digest, not the bytes.** `control` is the xxh3-128 of the comment-stripped line
  stream (`region_memo/control.rs::digest`, `directive_memo::context`); the record key frames that digest. `EXPANSION_VERSION` is 5
  and `DIRECTIVE_VERSION` is 7, so older records are ignored (one cold compile).
- **Not done:** the observation store `leased` bookkeeping (`dm-session/src/artifacts*`). It is the shared-roster store of daemon
  sessions only (a one-shot compile never leases), keyed by variant pointer, with deferred claims and a generation check through
  the held key owner, and about a dozen tests read `buckets` directly. A flat slab with hash index would save an estimated 300-400
  MB per daemon session; it needs its own lane.

## Shared ABI unit artifacts (lane `compiler/share-abi-artifacts`, 2026-10-26)

The largest owner a second root added was `driver_facts::abi_artifacts` (97 MB, shared store part 4). An ABI unit artifact is a pure
function of what its receipt reads (`Inputs`: the shared engine payload, procedure metadata by content, the predecessor layout, the
semantic answers), so the ABI store is now one daemon-wide core with a lease per session (`driver_facts/abi_store.rs`, purpose
`abi.units`; `DMB_SHARED_STORE_PRIVATE=abi` keeps it private, and a store that builds whole-batch recipes, `DMB_ABI_BATCH_REPLAY` /
`DMB_ABI_BATCH_RECIPES`, stays private because recipes bind to one session's frontend). The rules are the other shared cores': a
variant is found by exact key, validated against the asking session's own answers, claimed by the lease, and freed when the last lease
releases it. The scheduler (`abi_scheduler.rs`) visits the key's candidates through `visit_candidates`, prefers the variant this
session already claims over a sibling's, and claims the accepted variant when the row is finished (`ObservedArtifactLease::claim`,
new in `dm-session` with `visit_key_storage` reporting whether the lease holds a variant).

**Memory** (`bench/shared_store_probe.sh`, allocation-sites release build, same binary, `DMB_SHARED_STORE_PRIVATE=abi` against
sharing on; requested live after each request, GB):

| | root A | + second request of A (test variant) | + root B | sum |
|---|---|---|---|---|
| ABI store private | 6.80 | +3.53 | +2.24 | 12.57 |
| ABI store shared | 6.80 | +3.06 | +1.58 | 11.44 |

Sampled owner growth of root B fell from 2176 to 1475 MB: `abi_artifacts` (97), and with it the `lowering::symbolic_input` (151)
and `portable_meaning::meta` (82) payloads the private units held, left the list. Peak private memory of the three-build probe
15.55 -> 14.05 GB.

**Proof.** `bench/shared_store_equiv.sh`: all six interleaved shared-daemon builds (A game, B game, A test, B test, B game, A game)
byte-identical to their cold private-daemon references (pairs `d422acf6...` A game, `2fcde9cc...` A test, `2f841f3a...` B game,
`1ed11dbb...` B test), `dmb-equiv --all --ignore-debug` EQUIVALENT, no marker leak. Tests: `abi_store_tests` (a second session
claims the first session's variant, and it dies with the last lease), `leased` key-storage/claim test in `dm-session`.

**Timing** (warm patch rebuild, root A, one daemon per arm, three one-line edits to `code/game/world.dm` per round, arms
interleaved; the machine was loaded by other work and a game, so single runs vary by a factor of two). Two sessions: first
private 17.4-21.5 s (mean 18.8) against shared 12.6-18.6 s (mean 15.9); second, three rounds, private 11.4-18.8 s (median 16.1,
one 43 s outlier) against shared 10.4-19.4 s (median 15.3). No sign of the shared core being slower; within the 5 percent limit.
