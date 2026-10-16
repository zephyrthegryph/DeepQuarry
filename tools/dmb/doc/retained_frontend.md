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
