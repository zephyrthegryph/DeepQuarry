# Incremental core: one query database

Status: design, 2026-10-17 (lane `tools/dmb-decl-patch`). Replaces the special-case patchers with one mechanism.
Correctness oracle: `dmb-equiv` against a cold compile (2026-10-14 decision), never byte equality.

## Problem

A request today runs every whole-program stage and recovers reuse item by item (memos, receipts, domain versions). When the
declaration skeleton differs from the retained base, `body_patch::try_patch` gives up (`body_patch`, `append`, `default patch`,
the code-motion `LineMap` each cover one edit shape) and the full compile runs: 26-170 s on real worktree switches against a
5 s body patch. Cost left in a hot full compile is checking: lowering 6 s with every unit hitting, initializers 3 s, link 2 s,
composition 2 s. Reuse exists; dependency knowledge is not first class, so nothing can say "these N things are dirty".

## Model

A session is a database `Db` of memoized queries with a global revision counter. Inputs are file bytes (stamps and the watcher
already give this), the `.dme` order, defines and resource files. A query value stores `(value hash, deps, verified_at,
changed_at)`. Fetching in a new revision:

1. `verified_at == now`: green, return.
2. Walk `deps`; if none has `changed_at > verified_at`, mark verified (green) without running the query.
3. Else rerun. If the new value hashes equal to the old, keep `changed_at` (early cutoff): dependants stay green.

A full compile is "every input red"; a worktree switch, the test build (`-DCITESTING`, +11k bodies), a declaration edit and a
body edit are all different sets of changed inputs.

## Queries (after preprocessing)

| Query | Key | Depends on | Reuses |
|---|---|---|---|
| `expansion(region)` | region | its bytes, the macros it read | expansion memo, macro-read receipts |
| `file_decls(file)` | file content hash | its expansions | declaration chunk contributions |
| `type_rows(path)` | type path | `file_decls` of the files contributing rows, in `.dme` order | `KeyedDeclarations` |
| `type_resolved(path)` | type path | `type_rows(path)`, `type_resolved(parent)` | splice groups |
| `member_resolved(path, name, kind)` | the triple | that group's rows, `member_resolved` on the parent | `MetadataDependencies` |
| `proc_lowered(occurrence)` | header, body, owner (the existing key) | exactly the `member_resolved` / `type_resolved` / resource queries it read | lowering memo; its recorded `ResolveQuery` reads become edges |
| `initializer(type, var)`, `class_layout(type)` | the declaration | the same kind of resolved queries | initializer receipts, class projection |
| `link_entries(unit)` | the lowered unit | its symbolic references | `PreparedPatchRecord` relocations |

Domain versions (`ReadDomain`) are replaced by per-query `changed_at`: finer, since a read of `(owner, name)` no longer shares a
version with every other member of the tree. Reverse edges are kept so "who depends on X" is a lookup, not a scan of 98k bodies.

## Stable IDs

Type, proc, var and string IDs are slots in per-kind tables, assigned on first sight from the path hash through a persisted side
table (`path hash -> slot`). A slot is never reassigned while it lives; a removed entry is a tombstone, reclaimed only by
compaction (tombstones above 5 % of a table, or any cold compile, which restores fresh numbering). Orders the game can observe
(`typesof()`, class var and proc lists, map objects) stay in fresh order and are derived from the resolved queries, not from slot
order. A class inserted mid-table moves class IDs: those are fixed by a relocation-only pass over units that reference a shifted
class, no relowering. This reverses decision D10 in `DESIGN.md` (no history-dependent IDs); the 2026-10-14 decision already
accepts it, and a cold compile still gives canonical numbering.

## Incremental link and publication

Linking is per unit: a changed `link_entries` updates its slot entries and rewrites its words from relocations; unchanged units
keep their code rows. Class records, class lists and the Variables table are rewritten for changed classes only. Strings are
append-only with orphan counts. Encoding writes changed sections and recomputes the hash and string cipher over the tail; the
pair store write stays whole-file until a later step.

## Steps (each lands under the interim compiler rule, proven by dmb-equiv against cold)

Order revised 2026-10-17 after measuring a hot full compile: link plus composition cost 3-4 s; the rest is per-body and
per-initializer visiting (lowering 6 s with every unit cached, initializers 3 s, ABI and startup 2.5 s), the frontend (4-6 s) and
resources (2.4 s). So the first steps make the visiting stages dirty-set driven and keep link and composition whole-program, which
also gives fresh numbering and output equal to a cold compile.

1. `dm-query` core: revision, red/green, early cutoff, reverse edges, memory accounting. Tests. (landed)
2. Dirty-set driven lowering, initializers, ABI and startup: the dependency graph is the existing read index in `dm-session`
   (`incidence.rs`: domain to variant, certified sets) plus `dm-query` for the new declaration queries; a request visits only the
   units whose own key changed or whose recorded reads are dirty, and reuses retained link inputs for every other unit. Verify mode
   compares against the full walk. Link and composition stay whole-program.
3. Preprocessing, frontend and resources become queries: directive planning and expansion per file keyed by content hash plus the
   macros read (reverse index macro to reader regions), declaration parsing per file, resource demand per region and resource
   content per file (keyed by the references actually resolved, not folder listings), so an edit costs only its dependants end to
   end and the 9 s floor goes away. Subsumes `retained_frontend.md` stages 4-7 and the F1-F5 frontend revision steps.
4. Delete `body_patch`, the append patch, the default patch and the code-motion map once the query path passes the equivalence
   suite: add proc, remove proc, add var, remove var, change parent, rename type, add `#define`, the test-build switch
   (`deepquarry.test.dme`) and a worktree switch.
5. Only if the numbers justify them: stable-ID slot tables for procs, vars, strings and classes, and incremental link and
   section-wise publication (the sections above describe them).


## Declaration changes without a full compile (2026-10-18)

Measured on a hot session (pool-10, 8 workers, machine loaded): an unreferenced added var 11 s and an
unreferenced added proc 16 s already take the stable-numbering append patch (`body_patch_append.rs`);
an added type 37 s and a removal 82 s run the full path (frontend 3-5 s, ABI 2, initializers 3, lowering
9-11, required types 1-2, link 3, composition 3, publication 1-2). Lanes in the shared root hit the full
path on every declaration edit, and the append patch declined as soon as the new name was used anywhere.

Order of work, each slice proven by the six-session structural scenarios (retained output equivalent to a
fresh compile of every revision) and a production-tree A/B:

1. **Referenced additions.** A body that mentions an appended name is relowered with the edited bodies
   (word match over the expanded text; a mention outside every body, such as a var default, declines). An
   existing unit may change its link inventory and literals: new keys resolve through the append-extended
   tables, new literals are appended strings. Its procedure record (frame, ABI, features, instances,
   helpers) must stay equal, so the code-row splice remains sound.
2. **New types.** Append class records with stable numbering: the type row, its parent chain and
   proc/verb/var lists built by the existing class projection for that one owner, `typesof` order
   following the type table (an accepted order difference, as for appended procs).
3. **Removals and parent changes.** These move class layout and lists; until stable-ID slot tables
   (step 5) exist they take the full path, made cheaper by the dirty-set stages.
4. **Dirty-set full path for what remains**: lowering, initializers and ABI visit only units whose own
   inputs or recorded reads changed under the declaration delta; link and composition stay whole-program.

### General path for declaration edits (decided 2026-10-18)

Every declaration edit is a changed-input set on the one full path; no new special-case patcher. The
append patch stays only while it is faster and is retired when the general path matches it.

What stable IDs can and cannot buy, from the link code (`dm_link::LinkTables::build`): type, procedure
and string indexes follow the fresh inventory order (`inventory.orders`), and that order is observable
(`typesof`, proc tables, `vars`). Appending keeps every existing index for additions. A removal or a
parent change cannot leave a tombstone row in the class or procedure table without changing what the
game sees, so it renumbers; renumbering is a relocation of the words of every unit that references a
moved index, which is the link pass itself (about 3 s), not relowering. So the plan is:

1. **Dirty-set visiting (no ID changes).** Lowering, initializers, ABI and startup reuse every unit
   whose inputs and recorded reads are unchanged without visiting it: carry domain versions across
   revisions for domains the declaration delta does not touch (today 627k versions are re-issued per
   request, 1-2.5 s), and keep the previous request's completed inputs keyed by unit identity so a clean
   unit is not claimed and rebound (1.5 s). Link and composition stay whole-program. Expected: a hot
   declaration edit drops by the lowering, initializer and ABI visiting cost (about 6-10 s of 25 s).
2. **Per-class records as queries.** `class_projection` and `materialize_members` build every class
   record each request (whole-program). Key each class record by its owner's resolved rows and its
   parent's record; rebuild only changed owners and their descendants. This is what an added type needs.
3. **Stable IDs for additions, relocation for removals.** Link keeps the previous assignment for every
   surviving key and appends new keys (the append patch's numbering); a removal or reparent renumbers
   by relocating words, never relowering. Composition writes changed sections only.
4. **Model persistence.** The retained composed model is released under memory pressure, which turns
   the next declaration edit into a cold composition (seen 2026-10-18). Persist the model's row image
   and link answers on disk with the patch base so a released model is reloaded, not rebuilt.

Each step is proven by the six-session structural scenarios against fresh compiles and an interleaved
production-tree A/B.

## Coordination and risks

- The memory lane owns `SessionKey`, `BuildHost` keying and the budget. The session becomes the `Db`: eviction is by query kind,
  recomputable values first, inputs last. A defines change must not discard the `Db`, only redden the macro reads. Interface: it keeps
  `SessionKey` free of declarations; I add `Db` as a field and ask it for an eviction hook per query kind.
- Frontend (4-6 s) and resources (2.4 s) are whole-program per request until step 6 and bound the floor near 9 s; the floor is not
  permanent.
- Risk: the dependency wrapper must see every read. The existing `RecordingResolver` already gates lowering; the same gate must
  cover initializers and class layout. `DMB_QUERY_VERIFY=1` recomputes green queries and compares, as `DMB_DOMAIN_CACHE_VERIFY` does.

## Cross-request reuse of reuse checks (decided 2026-10-18)

A hot added-type compile (about 13.5 s, timing detail off) no longer recomputes much; it re-checks
everything. Per request: about 630k domain versions are issued (0.5 s wall), about 212k initializer
writes and 87k procedures each look up, certify and claim their stored result (lookup 1.4, certify
3.9, claim 2.9 CPU-s). The plan is to carry what did not change from the previous request instead of
re-proving it.

1. **Carried domain versions.** A tree certificate token is carried across a revision only while the
   domain's inputs are unchanged (demand-token carry, `inherit_demand_tokens`), and demanded tokens
   come from one process-wide issuer. So a (domain, token) pair seen with a positive tree answer
   still has that answer; the host issues its version from the token without resolving the query
   (`engine_host/carried_positive.rs`, `DMB_CARRY_VERSIONS`). Negative and Unsupported answers still
   take the full path: they depend on source-wide absence and runtime catalogs.
2. **Version diff instead of a full roster.** Keep the previous request's issued versions per domain.
   The certified roster becomes the previous roster minus artifacts whose read domains changed
   version (the incidence index already maps domain to artifact), so the 630k-domain certify pass is
   proportional to the changed domains.
3. **Bulk carry with one claim.** Artifacts of an unchanged roster are claimed into the new request's
   lease as one set (the previous lease's claims, minus the affected ones), instead of 920k claims.
   Initializer classification and the lowering roster share this path.

Each step is gated by the six-session equivalence scenarios and an interleaved A/B, behind a flag
until it is faster and equivalent.

Measured 2026-10-18 (hot added type, quiet machine): step 1 was implemented and reverted. A carried
(domain, token) memory hit 288k of 344k variable domains, yet roster versions stayed at 0.41-0.43 s.
Per issued variable domain the token lookup and carry check alone cost about 1.5 us of the ~5 us
elapsed, and the 55k misses only 0.1 CPU-s: version issuing is many small lock-and-map steps, not
query resolution. A reader lock on the demand-token map was also neutral. What remains per unit is
bookkeeping: lowering's claim-and-rebind is about 23 us per procedure (2.1 CPU-s for 87.6k:
claim, local re-match, rebind, admitted-read recording) and initializer visits about 25 us per
write. Steps 2-3 therefore have to remove the per-unit claim/observe work itself (one lease-level
transfer of the previous request's claims and recorded reads), not the version computation.


## Migration plan: one query path, no patches (decided 2026-10-18)

Goal (user, 2026-10-18): every build (cold, body edit, declaration edit, added or removed type, reparent,
define change, worktree switch, test and bench variants) runs one path, the `dm-query` database driving
each stage as queries with recorded dependencies, red/green revalidation and early cutoff. A cold build
is "every input changed". The patch system (body patch, append patch, alternate patch bases, default
patch, code-motion line map) is deleted, with its flags and tests, once the general path matches it.
Gate per step: six-session structural equivalence plus `dmb-equiv` against a cold compile on the
production tree for every edit kind; a byte-identical cold compile stays available for releases.
Performance may not regress on any edit kind against today (body edit about 6 s through the body patch,
added type 13-14 s, worktree switch); interleaved A/B.

### What becomes which query

| Query | Key | Reads | Replaces |
|---|---|---|---|
| `source(path)` (input) | canonical path | file bytes (watcher proofs) | prepared inputs, snapshot memo |
| `project` (input) | manifest | `.dme` order, defines, variant flags, engine template, compiler policy | request config hashing |
| `expansion(region)` | region | `source`, the macros it read | regions memo, frontend revision mode |
| `file_decls(file)` | file | its expansions | declaration chunk contributions |
| `tree_group(owner, name, kind)`, `type_node(path)` | the group / path | `file_decls` of contributing files, parent `type_node` | splice groups, `MetadataDependencies`, demand tokens |
| `answer(read)` | one `ResolveQuery` | the `tree_group`/`type_node` queries it consults, pinned catalogs | `ReadDomain` versions, certificates, rosters |
| `lowered(unit)` | unit identity | its body expansion, the `answer`s it read | lowering memo, candidate roster, local path |
| `abi(unit)`, `initializer(owner, var)`, `class_record(owner)` | declaration | `answer`s read | ABI receipts, initializer receipts, class projection store |
| `resources(region)` | region | resolved references, `source` of the files hit | resource demand/order memos |
| `link` | program | `lowered` keys, previous `link` value (stable numbering) | `RetainedBindings`, assignment recipe |
| `section(kind, slice)` | output section | `lowered`/`class_record` rows, `link` | composition rebuild, body/append patch splices |

The value of `answer(read)` is the meaning itself, so early cutoff stops at the first unchanged answer:
an added type re-runs the groups it touches and the answers that read them, and every unit whose answers
are unchanged stays green without a certificate check. Revalidation must be parallel and cheap (the
`Db` lock is one mutex today): step 2 shards it and verifies a whole level of dependants at once.

### Order (each step lands with equivalence green and deletes what it supersedes)

1. **Session database and inputs.** One `Db` per retained session; a request is a revision; inputs are
   `source`, `project`, resources and the engine template, set from the existing input proofs. The full
   path runs under a derived `program` query; a no-op request is green end to end. The on-disk
   session record and pair store stay: they are the database's persistence across daemon restarts
   until the database itself is persisted. (Landed: `query_db.rs`, about 0.1 s for 5.9k sources,
   unchanged captures recognised by identity.)
2. **`Db` scale.** Sharded node table, lock-free green check, batch revalidation of dependants, value
   eviction under the session budget. Benchmarked with 1M nodes.
3. **Frontend queries.** `expansion`, `file_decls`, `type_node`, `tree_group` as queries computed by the
   existing splice code (a group's value is its resolved rows). Deletes the frontend revision flag and
   its non-revision path, the demand-token carry and selection pruning.
4. **Answers and per-unit queries.** `answer`, `lowered`, `abi`, `initializer`, `class_record`; recorded
   `ResolveQuery` reads become edges. Deletes domain versions and issued certificates in
   `engine_host`, the unchanged-candidate rosters, lowering/initializer/ABI receipt admission and the
   lease claim bookkeeping (the bulk lease transfer is not needed).
   (Lowering roster landed: `answer(query)` inputs hashed from the current answer and one `unit`
   query per stored lowering record over the answers it read, owned by the session's `QueryDb` and
   held by `SessionSymbolicMemo`; it replaces the domain-version roster whenever a session database
   exists. Positive structural answers the tree's classified `ChangeSince` cannot reach are carried
   without resolving. Measured 2026-10-19, pool-10, hot body edit with `DMB_BODY_PATCH=0`: roster
   1.13-1.25 s -> 0.70-0.85 s steady state (first edit 2.7 s while read lists are built), wall
   unchanged within noise (13-15.6 s), peak +1 GB (705k answer inputs and read lists); dmb-equiv
   equivalent against a fresh compile for body and added-type edits.)
   (Answer table landed, 2026-10-19: `QueryDb` holds one answer per `ResolveQuery`, proven at most once
   per request (opened by `revise`, bound to the tree in `cold.rs`) and shared by every stage through
   `dm_session::AnswerOracle`: a `ReceiptAdmission` with an oracle certifies receipts by answers and
   issues no domain versions except for producer inputs. Lowering roster, initializer receipts and ABI
   semantic receipts use it. Hot body edit, pool-10: init.value.visit 3.5 -> 0.8 CPU-s, admission.certify
   3.2 CPU-s -> 0, domain versions issued 828k -> 575k, initializer stage 1.9 -> 1.3 s, lowering 2.3 ->
   1.9 s, peak about 9.9 GB (the dm-query unit nodes are gone); dmb-equiv equivalent for body and
   added-type edits.) The lowering request admission takes the same oracle, and the local claim no
   longer replays admitted leaves into a recorder it drops (one version per read): hot body edit
   12.2-12.7 s wall (was 13-15 s), local claim/rebind 3.7 -> 0.5 CPU-s, domain versions 828k -> 102k.
   Deleted: the lowering domain-version roster (`unchanged_candidate_roster`, its rejection diagnostic,
   `DMB_TIMINGS_DETAIL=2` roster dump) and the lowering store's incidence index; a memo without a
   query database offers no unchanged candidates. Hot body edit 11.3-12.4 s, peak 9.4 GB (was 9.8).
   Then deleted: the ABI incidence-qualified roster (`DMB_ABI_QUALIFIED_ROSTER`) and with it the whole
   generic incidence index of `dm_session::ObservedArtifactStore` (domain-version candidate rosters,
   local-input certificates, `visit_affected`, incidence accounting); ABI rows are validated per unit
   against the answer table on the worker pool. Session baseline 7.8 GB (was 8.0).
5. **Stable link by default.** `link` keeps every surviving index and appends; removals and reparents
   renumber by rewriting references in the affected units' words, never by relowering. Deletes
   `DMB_STABLE_LINK` and the fresh-order full path (a release build asks for fresh numbering).
   (2026-10-19: `DMB_STABLE_LINK` deleted; a retained link always stabilizes against its previous
   bindings and a build without them (one-shot, cold) numbers in source order. A revert is now
   equivalent to, not byte-identical with, the initial build; six-session asserts equivalence.
   Removal/reparent relocation without relinking is still open.)
   (2026-10-19, later: the class table follows DreamMaker's order (path-tree postorder, see
   `class_inventory/dreammaker_type_order.rs`) over engine and source types; composition renumbers
   the engine template's classes into it. Because `typesof()` observes that order, a table with a
   complete supplied order is never stabilized: an added, removed or reparented type renumbers
   the class table, which relinks (no relowering: lowered units are symbolic). Production reparent
   probe (a type alternating between two parents, then reverted): every revision dmb-equiv
   equivalent to a fresh compile and the revert to the initial build. Strings and procedures keep
   stable numbering.)
6. **Section-wise composition.** `section` queries over the retained model; only changed sections are
   rewritten, then encoded. Body edit must reach about 6 s here. Deletes `body_patch.rs`,
   `body_patch_append.rs`, `body_patch_lines.rs`, patch slots and alternates in
   `composition/generation.rs`, the default patch, `DMB_BODY_PATCH`, `DMB_PATCH_ALTERNATES` and the
   patch tests, replaced by equivalence tests over every edit kind.
   (2026-10-19, pool-10: landed as whole-stage early cutoff plus incremental link/composition.
   `stage_reuse`: the initializer stage keys on its configuration and the declaration inputs
   (expanded text outside bodies, every source position) and is valid while the answer table has
   the version it had when the products were published (`QueryDb::answers_version`: tree, answer
   world = the static resolver's Tree domain version, every resource search proven again when a
   request opens); answers proven under one tree and world are carried without resolving
   (442k resolves -> 3.9k per body edit, `DMB_QUERY_VERIFY=1` re-resolves every shared answer
   through each stage's resolver: 0 mismatches on the production tree). `retained_output`: after
   startup and ABI, when the answers, the program text outside bodies (blank lines aside), the
   body roster, the non-text inputs and the archive equal the retained output's, only bodies whose
   text or position changed are lowered and relinked against the retained tables, their rows
   spliced into the retained image; source lines are paired row by row between the two builds
   (`LineMap`) and retained initializer code and declaration warnings move with them. Deleted:
   `body_patch.rs` (skeleton/line-map admission), `body_patch_lines.rs`, `DMB_BODY_PATCH`,
   `DMB_STRING_PATCH`; the append and default patches live on in `declaration_patch.rs` until the
   general path absorbs them. Hot body edit 4.3-6.4 s (body patch was 5.6-7.4 s), body edit adding
   lines 4.0-4.7 s, added type 11.4-12.8 s (was 14.5-15.3 s); dmb-equiv equivalent against a
   fresh compile for all three.)
7. **Resources as queries.** Deletes the resource order and demand memos.
   (2026-10-27, compiler/resource-queries-1: tried memoizing resource literal discovery per expanded-text piece by its
   text digest; a hot body edit's `resources_maps` stage stayed 0.50-0.66 s against 0.53 s, so literal lexing is not
   where that stage goes, and the memo was taken out. Profiled (compiler/resource-queries-2, `DMB_TIMINGS_DETAIL=1`, now
   in the request log): of the 0.53 s, `InputValidation` is 0.35 s: every request re-proves the resource input snapshot,
   3858 files, 1705 folder listings and 13889 negative probes, through the directory proofs. Next: make those inputs
   `source(path)` queries of the watcher's directory proofs, so a directory whose cached proof is the one the snapshot was
   proven with is not walked again; demand admission (0.02 s) and archive authentication are already cheap.)
   (2026-10-27, compiler/resource-queries-3: **input snapshots are proven by watcher events.** The directory watcher
   (`fs_watch.rs`) keeps an ordered change log: every event appends the changed entry and its directory under one sequence
   number, a `WatchToken` (epoch, sequence) names a position in it, a loss (overflow, read error, sync timeout, a full log
   of 200k entries) starts a new epoch, and a newly armed root is logged as one changed subtree once its watcher is
   proven. A `SnapshotProvider` reports the position of its first observation (`watch_token`: the live file system at the
   call, `BulkFileSystemProofs` at its capture, a journal none), and an `InputSnapshot` remembers the position at which its
   facts were last proven entry for entry (`WatchMark`, private, absent from the wire and from equality). Validation then
   carries every file, folder listing and negative probe whose directory no event named since that position (and no
   subtree event above it, and that is watched by a healthy root and not behind a link), and asks the provider only about
   the rest; racy and identity-less entries and exact mode are proven as before. Marks travel with the facts: a capture is
   marked at its start (or its provider's proof position), a merge keeps the earlier mark of its parts (none if either has
   none), `select_files` keeps it, and a session record takes its stored snapshot's mark back after the decode (by
   record id). The first access of an entry in a while updates its last-access time, which the watcher reports as a
   change of the directory: such a directory is proven once more, never skipped. Measured, production tree (`rootA`
   copy), 4 workers, hot private daemons per arm, three unique edits per arm (an added proc, then body edits), arms
   interleaved pub/new/pub/new on a machine shared with a server benchmark: `native resource InputValidation` 0.33-0.95 s
   (published) against 0.058-0.109 s from the second edit on (the first edit after a cold build still proves everything,
   0.32-0.43 s); `resources_maps` stage 1.03-2.45 s against 0.50-0.66 s; 9758 of 9794 session-record files carried; edit
   wall median 8.4 s (6.97-17.4) against 7.7 s (6.74-8.99). `dmb-equiv --all --ignore-debug` of the daemon output after
   body edits and a new file in a resource search folder against a fresh `--no-daemon --no-cache` compile: EQUIVALENT.
   Cargo tests `input_snapshot::watch_tests` (carried directories, changed file, appeared negative, new listing entry,
   removed directory, exact mode, unwatched paths, capture and merge marks). The demand and order memos the step names
   were already gone; nothing else re-scans the snapshot on an unchanged request.)

Measured 2026-10-18 before step 1: the general path today on a hot body edit (`DMB_BODY_PATCH=0`)
is recorded below with the patch for comparison.

| Hot body edit (one body, pool-10, quiet machine) | wall | compilation stage |
|---|---|---|
| body patch | 6.8 s, 5.2 s | 1.4 s |
| general path (`DMB_BODY_PATCH=0`) | 15.5 s, 15.0 s | 9.7 s (ABI 1.6, lowering 2.0-2.5, initializers 1.8-2.0, link 1.7-1.9, composition 1.6-2.0) |

So the general path has to lose about 9 s of per-unit checking and whole-program link and composition
on a body edit before step 6 can delete the patch; steps 4-6 are where that comes from.


## Plan for the remaining patches (2026-10-23, lane `compiler/query-core-1`)

Open special cases: the numeric-default patch (`declaration_patch.rs`, `try_default_patch`) and the append patch
(`declaration_patch_append.rs`). Each is deleted when the general path (`retained_output`, whole-stage early cutoff) is
no slower on the same edit. Measured today, production tree, pool-5, 4 workers, hot daemon, one numeric default of an
unreferenced var changed (`var/initial_charges = 25` to `26`/`27`):

| Path | Compile wall | Why |
|---|---|---|
| default patch | 12.8 s (patch itself 1.8 s; the rest is frontend, resources, input proofs) | rewrites one Variables record |
| general path (patch removed) | 22.4 s (ABI 1.5, lowering 6.8, initializers 2.4, link 1.6, composition 2.0) | `retained_output` declines: "answers changed" |

So deleting the default patch now regresses that edit kind by about 10 s; it was tried and reverted, nothing deleted.
The cause is granularity: the retained-output admission compares one hash of all answers, so a changed var default (an
answer read by its initializer and by `initial()`) reddens the whole stage.

Steps, each landing alone, proven by `dmb-equiv` against a cold compile and the six-session scenarios:

1. Per-answer dirty set in `retained_output::admit`: replace the single answers hash with the set of changed answers and
   their readers (reverse edges in `QueryDb`), so the stage reuses every unit whose read answers are unchanged.
   - **1a (landed 2026-10-23, report only).** `QueryDb::answer_diff()` returns an `AnswerDiff` (ids of changed answers,
     count of fresh slots, slots held, whether the table was dropped). Each `AnswerSlot` carries `born` (first request)
     and `changed` (last request in which its hash differed from the slot it replaced, or from the hash a stored unit
     recorded when a proof asked it: `RequestAnswers::matches`). `admit` takes the `QueryDb` and appends the summary to
     the "answers changed" decline reason; the daemon logs `native answer diff:` once per request. Admit decisions are
     unchanged. Cargo tests in `query_db.rs`: one edited default changes exactly one answer; a body edit changes none;
     an added proc changes only the answers that named it; a fresh table finds the same one from recorded hashes.
     Findings that shape 1b: (1) the table is populated lazily by whichever stage asks, so the diff names only answers
     some stage asked, and a unit proof stops at its first differing read; (2) `admit` runs right after ABI
     preparation, before the initializer and lowering proofs, so a diff taken there is a lower bound: the end-of-request
     line is the complete one; (3) on a hot string-default edit and on the `initial(max_integrity)` edit the diff is 0
     changed answers, i.e. `answers_version()` reddens only because it folds in the tree identity, not because an
     answer any stored unit read moved (request 2 after a cold request 1: 1,036,017 answers resolved from the stored
     units' reads, 0 carried, 0 changed). Cost: the end-of-request scan of 1.04M slots took 13-16 ms per compile (0.07%
     of a 21 s hot compile); the per-slot bookkeeping is one extra map lookup and a 16-byte wider slot per resolved
     answer, below the noise of the compile wall (20.3-27.2 s hot, same machine, before and after). 1b should therefore gate on the diff (run the stage proofs first, or move
     `admit` after them) instead of on the hash.
   - **1b (landed 2026-10-24).** `retained_output::admit` no longer gates on `answers_version()` (tree identity folded in).
     It decides last, on the answers: equal version passes as before; otherwise the answer world and resource searches
     (`QueryDb::answers_context`) must be equal and `QueryDb::prove_against_base` asks again, under this request's tree,
     every slot marked at the retained output's publication (`mark_published`, a per-slot `base` hash plus the question,
     numbered per output in `OutputBase::marks`) and requires each to equal its marked value. The proof walks the marked
     table, not the answers some stage asked this request, so soundness does not depend on lazy filling or on a proof
     stopping at the first differing read; an answer first asked after the mark has no base and belongs to a new unit
     (admit relowers only changed bodies, the roster is unchanged). Declined: no marks (first request, declaration
     patches, a later marking for another output), table dropped since the mark, a changed answer. Cargo tests in
     `query_db.rs`: tree differs but every marked answer is the same (admitted); edited default, asked-about added proc
     (declined); the proof finds a change no stage asked this request; stale/zero/dropped marks (declined); a new answer
     is not compared. Measured finding: a var default, `initial()`-read default, added proc or added type edit now declines
     with "program text outside bodies changed", not "answers changed": those edits change the text outside bodies
     (`text_key`), and the answer world (the static resolver's `Tree` version) differs with the declarations too. They
     cannot be admitted by an answer gate alone; step 2 (re-evaluating initializers whose reads changed, and a `text_key`
     that tolerates the default's own row) is what admits them. Hot body edits keep the patch (13 s).
2. Re-evaluate only initializers whose recorded reads include a changed answer; splice their rows and the Variables
   records through the same `retained_output` splice used for bodies.
   - **2a (landed 2026-10-24).** `retained_output::admit` admits a pure numeric default edit (`tree.default_edits()`,
     relative to the retained output's own tree) without the `text_key` and answer-gate checks: `default_edit_records`
     proves that the rows outside bodies differ only in rows `var/<edited name> = <number>` (per-row hashes of both
     layouts; at most one changed row per edit, same head text), that no text reads `initial(<name>)`, and that each
     retained Variables record holds the old value. `splice` writes the new values through `patch_rows`, which patches
     the fixed-width Variables records after the row splice and drops the retained model (rebuilt from the image on
     demand); the model path (`patch_model`) sets the values too. Composes with changed bodies in the same request.
     Cargo test `numeric_default_edits_on_the_general_path_match_fresh`.
3. **Landed 2026-10-24 (compiler/admit-early).** The 3 s gap attributed to ABI preparation and startup validation running
   before `admit` was not there: the default patch ran the same startup capture and ABI preparation (`lower_selected`),
   and the general path's work after them is 0.41-0.45 s (admit 0.24-0.27 s, lowering none, splice the rest; logged as
   `native incremental output: ... (admit, lower)` with `before admit` for the preparation, 1.6-2.0 s hot). Same
   production tree, pool-c2, 4 workers, hot daemons (one per namespace, one with `DMB_DEFAULT_PATCH=0`), `initial_charges`
   edited 27 to 35 on a machine shared with other lanes: general path 10.7-11.4 s, default patch 12.4-13.8 s (8.0-8.7 s
   in the quiet measurement above, so the earlier gap was machine state). With the general path at or below the patch,
   `try_default_patch`, `DMB_DEFAULT_PATCH`, `disable_default_patch` and the patch-count test are deleted; `reads_initial`
   stays in `retained_output` (the admission proof uses it), as does `DefaultEdits` in `dm-tree` (the frontend's proof).
4. Same for appended callables (new link entries append), then delete `declaration_patch*.rs`.
   **Landed 2026-10-26 (compiler/one-path-decl).** `retained_output::admit` takes an edit that only appended procs, verbs
   or plain vars relative to the retained output's own tree (`tree.appended_callables()`): `retained_output_append.rs`
   (the former append patch, split into `admit_appended` and `splice_appended`) proves the alignment, the mentions and the
   line map; `cold::incremental_output` lowers the changed and appended bodies through the same selected-body lowering as a
   body edit, and `splice` appends the new procedures, records and list entries to the retained model. No answers are
   compared (every text naming an appended name is a relowered body or its own declaration) and no marking is made, as
   before. Deleted: `declaration_patch.rs`, `declaration_patch_append.rs` (moved), `cold/selected_lowering.rs`
   (`lower_selected`), the request runner's declaration-patch attempt, `RetainedGeneration::patch_variable_values` (dead
   since the default patch went) and `applied_with_declaration_patches`. Measured, production tree, 4 workers, hot daemon
   per arm, three edits per round (added proc, added proc, added `/datum/var` with a numeric default), arms interleaved six
   times on a machine shared with other lanes: published compiler (patch) 5.2-8.8 s wall, compilation stage 1.47-2.26 s;
   this branch 4.8-9.2 s, compilation 1.47-3.03 s (first edit of a session the slowest); the quietest pair: patch 5.24-5.56 s,
   general path 4.83-5.22 s. `dmb-equiv --all --ignore-debug --ignore-order` of the general path's output after the edits
   against a fresh `--no-daemon --no-cache` compile of the same tree: EQUIVALENT. Cargo tests `structural_change`,
   `six_session`, `revert_rebase`, `variant_spill`, `retained_output` pass.
5. Frontend queries (`file_decls`, `type_node`) and resources as queries lower the shared 9-11 s floor.
6. **Alternate bases and model recovery deleted (2026-10-26, compiler/one-path-state).** The retained model is now a
   function of the patch base's image: `RetainedGeneration::model_of` keeps the composed model when it encodes the base's
   image and otherwise decodes the image (accepted only when it re-encodes to the same bytes; 0.12 s decode + 0.12 s
   re-encode on the production image). That one rule replaces the model recovery after a release, the body-patch row
   ledger (`model_rows`/`model_anchor`/`rows_synced`) and the per-alternate models. Alternate patch bases
   (`DMB_PATCH_ALTERNATES`, `select_patch_base`) are replaced by the persisted state: when a full build replaces a base of
   other program text, the replaced base is written on a background thread to a spill file keyed by the variant and that
   text (`variant_spill::text_key`), and `admit` restores the stored base of the request's text (swapping out, and storing,
   a live base of other text) unless the edit is relative to the live base. Needs the compiler cache (`no_cache` off), as
   the daemon runs. Test `variant_spill_tests::lanes_with_different_declarations_build_on_their_own_stored_base` (each lane
   switch builds on that lane's base). Measured, production tree, interleaved hot daemons, per round body edit, string
   edit, appended proc, body edit, string edit: patch-path steps 4.2-9.1 s (step 1 compiler) against 4.6-8.4 s (this
   branch) apart from one loaded round; `dmb-equiv` of the chain's output against a fresh `--no-daemon --no-cache` compile:
   EQUIVALENT.
7. **Answers settled after lowering (2026-10-26, compiler/one-path-marks).** An admitted output's answer version, context,
   facts and mark are taken after the request lowered what it relowers (`Answered::settle`), not at admission: the
   answers and resource searches the relowered and appended units asked first are now part of the published mark, so the
   next request proves them too (before, a slot first asked after the mark was never compared). Appended-callable outputs
   are marked like any other (they were retained without marks). A decline on the answer world now says whether the
   world or the resource searches differ, and each request logs `native answer world: tree=... world=...`.
   A body edit after an append builds on it. (A measurement script that re-appended an edited proc at the end of its
   file moved that declaration after the appended one: the declaration order changed, the tree identity and answer
   world with it, and the edit correctly compiled whole.)


## Persisted dependency index, step 2 (2026-10-24, lane `compiler/dep-index`)

Measured first, because the 10-17 figure (345 s) was a loaded machine. A compile after the daemon was retired
(fresh `DMB_DAEMON_NAMESPACE`, one comment appended to a `.dm` file so the published pair is not current, shared disk
memos hot, 4 workers, production tree), compile stage times of `native stages` / `native compile`:

| | evicted session, warm OS file cache | evicted session, cold OS file cache | hot session (reference) |
|---|---|---|---|
| wall | 40-49 s | 94 s | 42 s (answers changed: full path) |
| input preparation | 1.3-2.4 s | 5.9 s | 1.3 s |
| frontend | 10-13 s | 33 s | 4.9 s |
| compilation | 21-26 s | 28 s | 11.4 s |
| ABI / lowering / initializers | 3.8 / 6.5 / 6.2 s | 7.3 / 7.7 / 7.5 s | 2.1 / 2.4 / 2.4 s |

The frontend is `DirectivePlanning` 2.2 s, `Expansion` 1.1, `DeclarationParsing` 2.3 and `TreeResolution` 4.7 (whole-program,
not persisted). Per-unit disk replay, CPU-seconds summed over workers (92.8k units): lowering `disk_reads_check` 9-12,
`disk_rebind` 4.7-5.8, `disk_decode` 1.2; ABI `disk_reads_replay` 3.0; initializers 10; domain versions issued 933k (12 s) and
1.3M tree resolves (22 s). The disk records already carry a `(Tree, version)` receipt, but it names the world the record was
*written* under, so a record admitted under any other world replays all its reads in every new process.

Landed: `dep_index.rs`. One record per (policy, world) in the shared compiler cache (stage 31; the cache's size and age caps
bound it, `DMB_DEP_INDEX=0` turns it off) holds the ids (hash of key and recorded reads) of lowering records whose reads were
proven current under that world; the world is the content-derived `Tree` domain version of the request's resolver
(declarations, scalar answers, procedure statics). A fresh session finds a record's id in the index and treats it as written
under the current world: its typed answers stand without resolving (domains the world fixes; engine catalogs and resource
searches are still checked) and its receipt names the world instead of one issued version per read domain. Measured, same
tree, evicted, index warm against `DMB_DEP_INDEX=0` on the same binary: lowering `disk_reads_check` 10.3 -> 2.5 CPU-s, lowering
disk lookup 18.3 -> 10.6 CPU-s, resolver memo hits 4.8M -> 1.9M, 89,974 of 92,836 records certified, none contradicted. The
output is byte-identical (same pair hash) to the index-off run and to a compile with an empty cache directory. Wall time did
not move (48.5 s against 48.8 s): the ABI replay (`abi.disk_reads_replay`) and the initializer receipts resolve the same 1.0M
queries and issue the same 933k domain versions, so the work only moved to whichever stage asks first.

Next slices, in order of what they remove: (1) ABI rows (`abi_disk.rs`) and initializer receipts take the same certificate;
the ABI wire needs a typed-answer sidecar like the compact lowering record, because its replay also records the reads into the
unit's receipt and a recorded read needs a `ResolvedMeaning`; (2) with all three stages certified the issued domain versions
and tree resolves vanish (about 34 CPU-s, 8 s of wall); (3) a persisted answer table keyed by the declaration delta against the
stored world, for the worktree switch where the world differs; (4) bulk persistence of directive planning, expansion and
declaration facts (about 5 s of the frontend); `TreeResolution` (4.7 s) needs the model persistence of the declaration plan.


## Persisted dependency index, step 3: ABI rows and initializer receipts (2026-10-24, lane `compiler/dep-index-abi`)

The ABI wire (`driver_facts/abi_disk.rs`, schema and cache version bumped) and the initializer wire
(`lowering_memo_wire_initializer.rs`, schema and key version bumped) now carry a typed-answer sidecar next to
their canonical reads: one `Option<PortableResolvedAnswer>` per read, aligned with `reads`. Their replays go through
`dep_index::replay_reads`. An id is hashed per scope (`Scope::{Lowering, Abi, Initializer}`, so the three stages share one
set per world without colliding); a record whose id the index holds for the provider's world takes the sidecar answer of
every world-fixed read (checked against the stored canonical bytes first) and resolves nothing for it. Every other read
resolves and compares exactly as before, and a record that replays clean is noted for the next session. `DMB_DEP_INDEX_VERIFY=1`
replays certified ABI and initializer records anyway and counts a differing read as `contradicted`.

Neither replay records its reads into a unit receipt any more. ABI: `BorrowedResolver` forwards `observes_reads()` and the
transparent receipt observer of the request's resolver, so the unit's `RecordingResolver` is transparent and the replay hands
it the admitted answers afterwards with `record_answer(.., None)` (no domain version is issued per read; the stored receipt
is judged by the answer oracle). Initializers: the replay resolves through the host unrecorded and the receipt is the replayed
answers plus whatever the modified-expression reissue read. One `DepIndex` is created per request in `runner_host.rs` and shared
by the lowering memo, the ABI transport and the initializer transport.

Measured (production tree, evicted session: own daemon namespace retired, one comment appended to a `.dm` file, shared disk
memos hot, 4 workers; the machine was loaded by other lanes, so wall times are noisy and the counters are the evidence):

| | step 2 (master 41dd15eb05) | step 3 |
|---|---|---|
| domain versions issued | 933k | 344k |
| tree resolves (tree_calls) | 1.325M | 726k |
| tree resolve CPU-s / version issue CPU-s | 29-34 / 12-17 | 17-20 / 4-9 |
| `abi.disk_reads_replay` CPU-s | 4.5 | 2.4 |
| compile wall, interleaved runs | 64 s, 91 s | 42 s, 61 s, 83 s |
| lowering stage | 12.8, 19.6 s | 4.6, 6.8, 8.1 s |
| index off (`DMB_DEP_INDEX=0`) | | 103 s, 933k -> 902k versions, 40 s lowering |

Not reached: the expected ~34 CPU-s. 185,378 of the 186,382 ABI reads (exactly two per unit, so presumably the mandatory `Ancestry` and `DeclarationChain` reads; not broken down by kind) and
25,937 of 71,204 initializer reads have no portable form (`PortableResolvedAnswer` covers scalars, values and symbols but not
`Symbols`, `Members`, `Member` or `Declaration`, whose payloads hold `ProcedureMetadata` and symbolic expressions with no
serde form), so they still resolve. The remaining 726k tree resolves are those reads plus the same reads of the lowering
records. The next step is a portable form of `DeclarationMeaning` (or a receipt that stores a canonical hash instead of the
typed answer for a certified read, which needs `Receipt`'s answer type to allow it); `Symbols` alone would not move the
number, since an owner's ancestry is shared by its units. Records are only noted when a replay passes, so a freshly computed row
certifies from the second compile after it was written; noting at stage time (its reads were just computed under the current
world) would shorten that to the first.

Proof: `cargo test -p dmbc` (1088 tests, new: `replay_reads_certifies_the_second_session_and_skips_the_world_fixed_resolves`,
`indexed_abi_rows_certify_in_a_later_session_and_prepare_identically`); `dmb-equiv --all --ignore-debug` of the indexed
evicted-session output against a cold `--no-daemon --no-cache` compile: EQUIVALENT; a `DMB_DEP_INDEX_VERIFY=1` run: 0 contradicted.


## Model persistence: a variant's patch base on disk (2026-10-24, lane `compiler/variant-spill`)

A variant (project, defines, compiler policy) keeps its last output as a patch base: the published image with its list rows
(`PatchImage`), the link answers (`PatchLink`: numbering, string contents, mob bindings, initializer code), the field records and the
source half (`OutputBase`: body roster, row lines, unit link footprints, inputs, archive, warnings, answer version). It is most of
what turns an edit into a body patch, and it is gone whenever a variant stash, an idle tier, a retire or a daemon exit drops it.
`variant_spill.rs` now writes it, one file per variant under `<cache root>/variant-spill/` (checksummed frames, the image raw and
verified against its digest, written aside and renamed), before each of those drops (`BuildHost::spill_patch_bases`, called by
`release_stashed_variants`, the compiler-artifacts tier, variant eviction, session release, retire, and a drop guard at daemon exit).
A base whose image is already stored is not written again. The directory is bounded by `DMB_SPILL_BUDGET_GB` (4) and
`DMB_SPILL_MAX_AGE_DAYS` (7) on every write and in the daemon's cache pass; `DMB_VARIANT_SPILL=0` turns it off.

The next request of the variant attaches the file (`attach_spill`, header only) and `admit` restores it lazily
(`restore_patch_base`) when the header's program text matches the request. Nothing is trusted: the admission compares the restored
source half with the request exactly as it compares a live one. What is not stored and how admission copes:
- unit symbolic records: a patch compares footprints only, so units are stored as footprint digests (`UnitBase::Digest`);
- the retained model: decoded from the image when an edit needs one (`RetainedGeneration::model_of`);
- the expanded program text: row source lines are stored (`RowLines`), numeric default edits are not admitted on a restored output;
- the answer marks: a restored output proves its answers from `AnswerFacts` (declarations identity, answer world, every resource
  search with its answer hash; `QueryDb::answer_facts`, `prove_facts`). Its version and facts are retaken after the proof, and
  no marking is made for an output restored or patched from a restored one (the table of this process is not a complete record).
  A declaration edit therefore compiles whole, as before.

Measured on the production tree (pool-c2, machine shared with other lanes, so only ratios mean something; a body constant edited
before each compile): with the stash dropped under pressure the master compiler recompiled the dropped variant whole (test 89-96 s,
game 79-175 s), while the same drop with the spill restored it (restore of a 104 MB image 1.6 s, whole compile 60 s of which startup
and ABI preparation were 23 s under heavier load); a stash still resident patches in 10-20 s either way. Files were 123 MB (game) and
164 MB (test), written in 2-3 s.

Proof: `cargo test -p dmbc` (new: `variant_spill_tests` through the real request pipeline, restore after release, moved lines and new
strings, declaration edit, damaged/truncated/foreign files, retire and idle pass; `facts_prove_a_stored_output_in_a_table_that_starts_empty`),
`dm-link` and `byond-dmb` unit tests for the restored tables and row image.

Daemon restart (own namespace, retire between steps, same output directory): after game 70 s and test 153 s whole compiles, a
retired daemon stored 123 MB and 164 MB; the restarted daemon restored them in 0.7 and 0.8 s and compiled the edited game in 28 s and
the edited test in 33 s (a whole compile after a restart was 70-190 s; 280-310 s on a cold file cache). `dmb-equiv --all --ignore-debug`
of each restored-and-patched output (game, test) against a cold `--no-daemon --no-cache` compile of the same tree: EQUIVALENT.
The stored `generated_outputs` input record names the output location, so a request that writes elsewhere (another
`--artifact-directory`) is declined by admission and compiles whole. Remaining cost of a restored patch is the frontend
and startup/ABI preparation (the next lanes: persisted frontend facts, dependency index). `cargo test -p dmbc` 1096 passed.
## Persisted dependency index, step 4: portable declaration answers and stage-time certification (2026-10-24, lane `compiler/dep-index-3`)

Broken down first (`DMB_DEP_INDEX_KINDS=1` adds the untyped reads by query and answer kind to the `native dependency index` line):
all 185,380 untyped ABI reads were `Ancestry -> Symbols` (92,690) and `DeclarationChain -> Members` (92,690), and all 25,937
untyped initializer reads were `Ancestry -> Symbols`. Nothing else.

Landed:

- `dm_ir::PortableMeaning` (`dm-ir/src/portable_meaning.rs`) is the serde form of a `DeclarationMeaning` that the declaration
  chunk facts already had privately in `dm-tree/src/chunkfacts.rs`; it moved to dm-ir (chunkfacts uses it, wire layout
  unchanged) and `PortableNames` says whether a decode checks spellings against a symbol table. `PortableResolvedAnswer` gained
  `Symbols`, `Members`, `Member` and `Declaration` (an opaque inherited base keeps its owner and type knowledge);
  `capture_declared()` produces them and `capture()` keeps producing the scalar forms. `restore()` is now fallible. A restored
  answer is only ever used after its canonical bytes equal the stored ones, so the form carries no authority of its own.
  Not portable (still resolved): procedure statics and retained procs.
- ABI rows, initializer records and compact lowering records store `capture_declared()` answers (schema numbers bumped, so one
  recompute). A record too large with them falls back to scalar answers. The compact lowering record restores a compound answer
  the first time a certified read uses it (`VerifiedAnswers`), not in `preflight`; scalar answers are still checked at decode.
- Certification at stage time: `dep_index::staged()` notes an ABI row and an initializer record the moment it is computed
  (its reads were just resolved through the request's provider, so they are current under its world), and the compact lowering
  record is noted in `DiskWriter::queue_compact` with the id `encode_with_id()` computed. A new row therefore certifies in the very
  next compile instead of the second one.
- `CurrentReads::for_host` compared `&dyn Resolver` with `ptr::eq`, which includes the vtable; one provider type has a vtable
  per codegen unit, so the certified handoff to `disk_admission` failed and every read was re-resolved and re-versioned there
  (29 of 65 sampled `domain_version` calls). It compares the object address now (`ptr::addr_eq`).

Measured (production tree, evicted session: fresh daemon namespace, one comment appended to a `.dm` file, 4 workers, a cache
directory warmed by one earlier compile of the same binary; the machine was loaded by other lanes, wall times are noise, the
counters are the evidence):

| | first compile (cold cache) | evicted session, index on | evicted session, `DMB_DEP_INDEX=0` |
|---|---|---|---|
| domain versions issued | 933,280 | 343,663 | 901,733 |
| tree version issue calls | 1,325,294 | 726,091 | 1,296,873 |
| ABI reads typed / untyped | 0 / 0 (92,690 rows staged) | 186,384 / 0 | n/a |
| initializer reads typed / untyped | 0 / 0 (10,091 staged) | 71,201 / 0 | n/a |
| records certified (lowering / ABI / init) | 0 | 89,976 / 92,690 / 10,091 | n/a |
| compile wall | 154 s | 109 s | 191 s |

Index-on against index-off on the same cache and binary: issued versions 901,733 -> 343,688 and tree issue calls 1.297M -> 726k
(the earlier slice's 344k / 726k figure is what the vtable fix restores). `DMB_DEP_INDEX_VERIFY=1` replays every certified ABI and
initializer record and compares each stored answer: 0 contradicted over 92,690 + 10,091 records, lowering 0. Output: the pair hash
is identical in every run (also against a cold `DMB_DEP_INDEX=0` compile with an empty cache), the DMB and RSC are byte-identical,
and `dmb-equiv --all --ignore-debug` reports EQUIVALENT. `cargo test -p dmbc -p dm-ir -p dm-tree`: 1087 + 83 + 327 pass (new:
`declaration_chains_round_trip_through_the_wire_with_identical_canonical_bytes`; `indexed_abi_rows_certify_in_a_later_session...`
now expects certification and zero untyped reads in the second session).

What still issues versions (traced by sampling `domain_version` callers on the indexed compile): class projection prefetch and
initializer classification record their reads through `RecordingResolver::resolve`, which issues one version per read domain
(about 340k of the remaining calls); neither replays a stored row. Directive planning and input scan (item 2) were not changed:
the directive and expansion records are already persisted by content (`DiskExpansionMemo`, stage 4/1), and what remains is the
sequential replay of 5,956 directive lookups on the planning thread (`native directive lookups: disk=` 1.6 s idle machine,
3.7-6.3 s loaded), not missing persistence; moving it needs a parallel pre-decode keyed by the previous plan's regions.

## Frontend queries, step 3 (2026-10-25, lane `compiler/frontend-queries`)

What a hot one-file edit used to cost in the frontend (production tree, resident daemon, quiet machine): directive planning 0.57 s
(full replay, or 0.11 s for a directive-free leaf file through the single-file edit path), expansion 0.3 s, declaration parsing
0.7-0.9 s (of which 0.5 s was the client pipe: a progress line per 8 chunk results stalled every parse worker), origins 0.15 s,
tree resolution 0.04 s for a body edit and 0.7-1.1 s for a declaration edit, body indexing 0.1 s.

**What landed**

- *Source changes are a database query.* `QueryDb::revise` keeps a log of what each revision changed or removed
  (`RevisionChange`, 64 requests) and implements `dm_preprocess::SourceChanges`: `revision()` is a token naming the database
  and its revision, `changes_since(token)` is the union of every later request's changed sources, or `None` when the log does
  not reach back, the token is another database's, or a restart renumbered it. The provider the frontend reads
  (`PreparedSourceProvider::with_changes`) serves both through `SourceProvider::{revision, changes_since}`, and a plan records the
  revision it was made at. The O(files) comparison of every source against the previous plan is gone.
- *The ordered directive pass is memoized by include subtree.* Every include subtree it visits leaves a `SubtreeRecord`
  (`regions/plan_trace.rs`): the occurrences, regions and ordered items it made (as counts; positions live in the plan's
  `PlanTrace`), the pass state it started in and ended in (macro environment with an incremental order-independent
  fingerprint, open conditionals, `FILE_DIR` stack, `#pragma multiple` set), every include-once decision, the files it read
  and the dependencies it added. Two ways to use the previous plan, one result (`plans_equal`, unit tests and
  `DMB_FRONTEND_VERIFY=1` check it against a full pass):
  - *Patch* (`regions/plan_patch.rs`): with the change log, only the outermost changed subtree of each changed file is planned
    again, from its recorded start state; it replaces the old subtree when it visits the same files, reads the same includes
    and ends in the same state (early cutoff: nothing after it can differ, so no later position moves). Otherwise `None`.
  - *Adoption* (`adopt_previous`): the ordered pass itself adopts every subtree whose files (same text), start state, include
    context and include-once decisions are unchanged, copying its occurrences, regions and items renumbered; the others run.
    A manifest edit or a `#define` that changes the state every later subtree starts from takes this path.
- *Expansion copies what the plan copied* (`regions/reuse.rs`): a region that is a verbatim copy (the plan says which, and a
  post-pass finds the manifest's own regions that equal the previous ones) keeps its text, receipt and origin rows, moved in
  runs; only the other regions go through the expansion memo. Admission keys travel with the regions.
- *Smaller passes that no longer visit everything*: the source index is reused for a patched plan; origin and body lookups
  follow a row hint and a file hint (`partition_point_near`); the symbol table updates by delta when a few leaves changed; a
  stored declaration is not published again; whole-owner callable certificates (read by nothing in a build) are computed when
  asked; the progress line per 8 chunks became a time-driven one (250 ms).
- *Deleted*: `DMB_FRONTEND_REVISION` (`RevisionMode`), `plan_regions_edit`, `expand_regions_edit`, `RowEdit`/`spliced`.
  `DMB_FRONTEND_VERIFY=1` replaces the verify mode.

**Measured** (pool-c2, interleaved A/B: the published compiler and this branch's, each with its own resident daemon started from
a real compile, every source state compiled by both in alternating order; stage times of the request log; the machine was shared
with other lanes, so a round with a loaded machine is dropped from the ranges):

| One-file edit, hot | frontend before | frontend after | request wall before | request wall after |
|---|---|---|---|---|
| body edit in a file with directives | 1.7-2.1 s | 0.31-0.36 s | 5.3-6.4 s | 3.9-4.4 s |
| body edit in a directive-free file | 1.06-1.18 s | 0.29-0.32 s | 4.4-4.9 s | 3.7-4.0 s |
| declaration edit (added var, then one default) | 1.85-1.98 s | 0.88-0.97 s | 5.6-6.6 s | 4.4-5.0 s |
| `#define` edit | 4.3-6.8 s | 4.1-4.9 s | 17-20 s | 17-21 s |

A `#define` edit changes the state every later include subtree starts from, so the ordered pass replays them (the same work as
before, minus the expansion rows it moves); its request is dominated by the full relowering the compile stage does ("program text
outside bodies changed"), not by the frontend.

Where a hot leaf body edit spends its 0.3 s now: plan 0.01 s, expansion 0.03-0.08 s, source index 0.0, declaration parsing
0.11 s (leaf claims 0.07 s, one chunk parsed), origins 0.07 s, tree 0.04 s, body indexing 0.07 s.

**Equivalence** (production tree; the same sequence in the production world and the `-DCIBUILDING -DCITESTING` world: cold, body
edit, body edit adding a reference, added var, changed default, added proc, added type, `#define` edit, then the reverts): the
incremental output of this branch has the same pair id, `.dmb` hash and size and `.rsc` hash as the incremental output of the
published compiler at all 22 steps; against a cold `--no-daemon --no-cache` compile of the same source the pair id is identical
for the body edits and every revert, and `dmb-equiv --all --ignore-debug --ignore-order` says EQUIVALENT at all 22 (the
declaration, proc, type and define steps differ from a cold compile in table order only, as the append numbering does in the
published compiler). `DMB_FRONTEND_VERIFY=1` on the production-world sequence logged "incremental plan equals the full plan" and "reusing
expansion equals the full expansion" on every request that had a previous plan, and no mismatch.

**Not done, and why**

- `file_decls`, `type_node` and `tree_group` as database queries. The tree is dense: member ids follow declaration order, so
  a spliced declaration renumbers every later member and the splice, the dependency graph capture and the demand-token carry
  each walk all 342k members (0.13-0.4 s each). A key-based `tree_group` needs the stable-id tables of step 5 first.
- Deleting the demand-token carry and selection pruning. `issue_domain_version` still issues 109k domain versions per request
  (`native domain memo: issued=...`) and their consumers compare tokens across requests; without the carry every token changes
  and everything those versions guard is redone. They go when the remaining domain-version consumers move to answer hashes
  (step 4's last deletion). The carry itself is 0.13-0.28 s of a declaration edit.
- Declaration chunk cells (parse 0.11 s, origins 0.07 s and body indexing 0.07 s still visit every chunk or declaration).


## Domain-version tokens are content digests (lane `compiler/shared-store-4`, 2026-10-25)

A domain version (`Resolver::domain_version`, a `(ReadDomain, u128)` receipt) certifies that every read recorded under that
domain still has its recorded answer. The owner-scoped tokens used to come from process-wide counters, one number per issued
input state, so two sessions (two worktree roots, the test variant) with identical declarations held unequal tokens and nothing
that stored a token (rebound lowering records' `versions`, the domain memo, name-demand receipts, `MetadataDependencies`) could be
shared by content.

**Contract.** `token = xxh3_128(tag, artifact key, canonical encoding of the exact input state the token certifies)`
(`dm-tree/src/token_digest.rs`: every variable part length-prefixed, every optional part with a presence byte). A token changes
**iff** the encoded state changes, up to the 128-bit digest width:

* *Equal state, equal token* in every session and after every restart (symbols are text hashes, so no session-local id enters).
* *Different state, different token.* The encoding covers every field the artifact's `PartialEq` compares, because the old
  issuer reused a counter value exactly when the store's exact-read replay found an equal state. Nothing was added to or removed
  from the answers; only the name of an equal state changed from "the number the first session drew" to "its digest".
* A state that returns to an earlier value (A, B, A) returns the earlier token. That is sound: a recorded read under the token
  was computed from state A and still holds in state A. The counter issued a fresh number there and caused a spurious miss.
* Chains stay chains: a name's token at a type includes its parent's token (`parent_certificate`), so an ancestor change moves
  every descendant's token, exactly as before.

| Token | Digest of | Where |
|---|---|---|
| callable (whole owner, demanded selection, override chain, presence) | key, local members (key, definition, content (override chains only), metadata fingerprint, predecessor), engine intrinsics, parent token, both completeness gates | `owner_metadata/callables.rs`, `demanded_selections.rs` |
| variable | key, ancestors, parent token, local members, intrinsics, gates | `owner_metadata/variables.rs` |
| hierarchy | key, ancestry path list (the domain version is that digest shifted left with the hierarchy-certified bit) | `owner_metadata/hierarchy.rs` |
| member-name / selector | key, presence flag / selector bits | `demanded_selections.rs` |
| uniqueness certificate | key, reduced slot, non-unique flag, completeness | `resolver/storage_uniqueness.rs` |
| procedure static layout | procedure identity and every declaration's canonical bytes | `procedure_static_layout.rs` |

Content-insensitive selections keep ignoring `content` (the selection kinds below 6 pass 0), because their recorded reads never
depend on it; that is part of what the token certifies and unchanged.

`ReadDomain::persistent_version` is unchanged: these domains still never authorize a disk record. A digest could, but the
classification also records that the *host* tied the answer to process-local facts (fallback receipts, catalog issuers), so
lifting it is a separate decision.

**Still counter-issued** (process-local, not per-session-state): scalar-artifact certificates
(`constant_resolution_artifacts`), callable-fallback receipts (`runner_facts_callable_fallback`), engine provider and catalog
issuers (one per captured engine snapshot, shared by every session of the engine), `query_db` ids. Each certifies an admission
event, not a content state; converting them needs the transitive reads of the artifact in the digest.

**Consumers that assumed a counter.** `EngineResolverHost` packed a tree token into the high half of a `u128` next to a 64-bit
provider half (`(base << 64) | provider`, and `u64::try_from(token)`), which silently declined every version once tokens were
128-bit digests (five `dmbc` tests caught it). `engine_host::compose_version(base, tail)` now digests the pair; the catalog,
variable-negative and callable sites use it. `variable_negative_tests` and `owner_domain_tests` assert against it.

**Measured effect** (shared-store probe, requested-live GB; roots A and B are copies of the tree, B with comment-only edits, so
their outputs are byte-identical): A 6.28 / test +3.74 / B +1.94 before, A 6.60 / test +3.38 / B +1.87 after (one probe differs
from another by about 0.15 GB). The lowering `versions` list (124 MB, the largest B owner) is gone from B's growth because a
rebound record's list now equals its predecessor's and is shared. The rest of the owners the tokens were meant to unlock
(`domain_memo` 57, `MetadataDependencies` 59, the per-tree demand token map in `RetainedMetadata`/`demanded_selections` about
50, all of them per-tree caches keyed by selection) are caches of a pure function of the tree, not stores of content, so equal
tokens do not let two trees share them: sharing needs a tree-state identity to key a whole-cache share on, or a cheaper
representation, and is not done here.

## Shared output images (same lane)

The encoded `.dmb` a session retains for splicing (`byond_dmb::dmb::codec`, about 70 MB) is interned by content in a weak
daemon-wide pool (`dmbc/src/output_pool.rs`, installed through `byond_dmb::dmb::set_image_interner` by
`shared_store::activate`; `DMB_SHARED_STORE_PRIVATE=images` keeps it private). The writer hands every finished image to the
pool before any holder (`Generation`, the list-row encoding, the patch base) clones it, the digest is the one the writer
already computed, and a hit is decided by the bytes. Two sessions that publish equal outputs (a second worktree at the same
commit) retain one image; unequal outputs (the test variant) share nothing.


## Test variant as an increment over the game build (design, 2026-10-26)

**Today.** The unit-test world is a define set (`-DCBT -DCIBUILDING -DCITESTING -DDEBUG`; `CIBUILDING` defines `UNIT_TESTS`) on the
same `deepquarry.dme`. `runner_host::switch_variant` stashes the define-dependent state and the test build retains its own copy of
nearly everything: about +3.5 GB over the game session (audit 2026-10-26: link relocations 100-300 MB, codec output buffers 75,
`OutputBase` 145, lowering leases 160-440, lowering rebinding 150, directive plan 137, initializer classification 119, ABI artifacts
81, `RequestAnswers` 67-80, preprocessor plan items 119, joined text 60). Two things make it a near-duplicate rather than an
increment: (1) every per-unit record is admitted under the answer world, which is keyed by the whole `Tree` domain version, and the
test tree differs from the game tree (about 11k extra test bodies, 109 files with `#ifdef UNIT_TESTS` guards), so no game record's
world certificate holds and every answer is asked again; (2) initializer, map and modified-instance lowering branch on `DEBUG`
(`modified_initializers.rs` `source.ops`, `map_artifacts.rs` `ops`), so their records differ even where the source is equal.
Procedure lowering is already `DEBUG`-independent: the memo key carries `facts_policy` without the `DEBUG` byte and debug ops are
selected at link.

**Target.** A test build after a game build of the same tree costs at most 1 GB more and compiles as an edit of the game build:
every unit whose reads are equal in both worlds is the game unit (one record, two leases), and only units that read something the
defines change (guarded bodies, the extra test types, answers that name them) are computed for the test variant.

**Steps** (each lands alone, proven by `dmb-equiv` against a fresh `--no-daemon` compile of both variants and the six-session
interleaving; memory by `bench/shared_store_probe.sh` game then test):

1. *Answers keyed by what they read.* An `answer(read)` already hashes its value; admission of a stored unit should compare the
   unit's recorded answers (per-answer, as `prove_against_base` does for the retained output) instead of requiring its world
   certificate to equal the request's `Tree` version. With content-digest domain tokens (shared store part 4) two sessions on
   different trees that give equal answers to a unit's reads hold equal tokens, so the record is admitted and claimed by both.
   The dep index's world key (`dep_index.rs`) becomes a hint: a record whose world differs is checked by its answers, not
   replayed from scratch.
2. *`DEBUG`-independent initializer, map and modified-instance lowering.* Lower them without `DbgFile`/`DbgLine` and add the
   debug ops at link from the positioned code (`PositionedCode` already carries origins), as procedure bodies do; the memo and
   classification keys then use `facts_policy`. The test variant reuses every game initializer whose reads are equal.
3. *Shared per-variant indexes by content.* The directive plan, preprocessor plan items and joined text are per-file
   functions of (file bytes, start state); key them by that pair in the shared store so the two variants share every file whose
   start state is equal (the files before the first `#ifdef UNIT_TESTS` that matters, and every file whose guards do not change
   its state). `OutputBase`, link relocations and output buffers are per output and stay per variant, but the test variant's can
   be stored as a delta over the game variant's (chunked image, roster delta; see retained_frontend.md "What is left").
4. *Measure*: test-variant extra (target <= 1 GB) and the warm test build after a game build (target: the time of a
   declaration edit of the size of the define's effect, not a full compile).

**Coordination.** A DM-side lane reduces `#ifdef UNIT_TESTS` guards in engine code so fewer game bodies differ; it records its
progress here. The compiler side does not depend on it: steps 1-3 share whatever is equal.


## Domain versions to answer hashes (step 4's last deletion; started 2026-10-26)

Where versions are still issued, measured with a sampled caller probe (production tree, 4 workers): a hot body edit in a
session issues about 250 (ABI admission); a fresh-session full compile issued 909k domain versions (`issue_s` 8-10 CPU-s)
plus 1.30M tree version calls (`tree_s` 17-19 CPU-s). By caller, the full compile's issues were: stored lowering records
from disk (`lowering_memo_wire::current_reads` computing the current version of every read domain, and `transparent_reads`
covering reads by those versions), about 60 percent; the ABI and initializer receipts' recording resolvers
(`dm_session::reads` recording a version with every read: initializer classification, the ABI evaluator, non-text capture),
most of the rest; dependency-index replays a little.

**Slice 1 (2026-10-26, compiler/answer-hashes-1): lowering records under the answer table.** In a session with a query
database every stored lowering record is proven by the answer table instead of domain versions: `lookup_record` asks the
`RequestAdmission` oracle only (`ReceiptAdmission::has_oracle`; no `matching_domains`), and a compact record from disk is
admitted by `answered_reads` (each recorded answer's hash must be the table's current one; the typed answer is then taken
from the record without resolving) with no `CurrentReads::versions`, no version in the observer's record and an empty
version list in the promoted resident record (`CurrentReads::answered`). Records keep their stored versions on disk for
processes without a table. Measured, fresh daemon per build, the published compiler against this branch, interleaved:
full compile 30.6 / 35.6 / 36.0 s (compilation stage 17.5 / 21.3 / 20.6 s) against 27.1 / 32.9 s (15.3 / 19.1 s; a third,
loaded, 58.7 s); versions issued 909k -> 345k, `issue_s` 8.2-9.9 -> 2.6-3.8 CPU-s, tree version calls 1.30M -> 0.74M; hot
body edits unchanged (250 issued, 3.9-4.7 s). `dmb-equiv --all --ignore-debug` of the daemon output after the edits against a
fresh `--no-daemon --no-cache` compile: EQUIVALENT (two rounds).

**Slice 2 (2026-10-26, compiler/answer-hashes-2): ABI and classification receipts record no versions under the table.**
`dm_session::RecordingResolver::with_versions(resolver, false)` records reads with no domain version; the ABI evaluator's
recorder (`abi_artifacts::prepare`) and the initializer classification recorder use it when the session has a query
database (their admission already takes the answer table as oracle). Measured as slice 1, slice 1 against this branch:
versions issued on a fresh-session full compile 345k -> 112k (`issue_s` 3.4-4.5 -> 0.9-1.2 CPU-s), on a hot body edit
250 -> 1; tree version calls 739k -> 458k, but their CPU time rose (14-16 -> 24-26 CPU-s: the answers are now resolved
through the tree's own certificates), so the compile is unchanged within noise (compilation stage 19.4 / 22.1 s against
18.6 / 23.8 s; body edits 1.6-1.9 s against 1.4-1.8 s). `dmb-equiv` against a fresh compile: EQUIVALENT, three rounds.

Remaining issuers on a fresh-session full compile after slice 2 (caller probe, 1/64 sampled): the engine host's own
issuance (`issued_domain_version` through the scalar snapshot) for the receipts that still record versions, and the class
projection's retained owners (`class_projection::retained`, a `RecordingResolver` over the `SemanticTree` whose receipts are
admitted by `visit_explained` against the tree with their versions: about 340k tree version calls). The class projection
reads the tree, not the engine host the answer table answers for, so it needs a tree-level answer table (or to read
through the request's table) before its versions can go.

Next slices: (3) every request gets an answer table (one-shot compiles too), after
which the version path of `ReceiptAdmission`, `ObservationLedger::versions` and the stored version lists can go; (4) the
answer world (`QueryDb::begin_answers`) is computed from the tree and scalar snapshot directly instead of through
`domain_version(Tree)`, the dep index keys on it, and `Resolver::domain_version`, the engine-host issuers and dm-tree's
owner certificates and demand tokens are deleted.

## Design option: the include spec as the project input (2026-10-27, lane `tools/generated-dme`)

Not built; recorded for the query-core work. `deepquarry.dme` is generated now (`tools/build/gen_dme.py` from the files on disk and the
ordering spec `tools/build/dme_spec.txt`: `scan` roots, `skip`s, `first`/`last` groups, `before` rules, each with its reason; the
order dependences were found by compiling the generated order against the old hand order and comparing with dmb-equiv,
`tools/ci/dme_order_equiv.sh`). The `.dme` stays on disk because DreamMaker, DreamChecker, the analyzer and CI read it.

dmbc could take the spec directly instead of parsing the generated manifest: the `project` input row would be the spec text plus the
directory listings of the scan roots (names only), and the manifest order a query over them (`manifest_order(spec, listing)`, the
same stable topological sort). What it would buy:

* A file added or removed changes one listing entry, not a 5,900-line manifest whose text the frontend diffs region by region today
  (`program text outside bodies changed` declines incremental output on any manifest edit, which is why a lane that only adds a file
  pays a structural change).
* The order rules become typed edges the frontend can check: a macro use before its `#define` (what `gen_dme.py --check` reports
  heuristically) is visible exactly in the preprocessor's expansion facts, so the spec could be verified by the compiler instead of a
  token scan.
* The include position of a file stops being an input of every file after it: today's `.dme` order is a total order, while the spec
  only orders what genuinely depends on order (macros, the definition precedence of a proc defined twice on one type, global
  initializer order); everything else could compile in any order, which the per-file queries already assume.

What it costs: dmbc must reproduce `gen_dme.py`'s sort byte for byte (or call it) so DreamMaker, which still reads the `.dme`, sees
the same order; a disagreement would be a native-vs-DreamMaker difference the CI cross-check (`tools/ci/dm_equiv.sh`) catches. Keep
the `.dme` either way.


## `#define` edits: re-plan only the include subtrees that read the changed macros (step 5, started 2026-10-26)

An include subtree's directive interpretation depends on the macros its directives read (`#if`, `#ifdef`, `defined()`,
directive-memo hits) and write (`#define`, `#undef`), not on the whole incoming environment. Each `SubtreeRecord` now keeps
those names (`tested`); the ordered pass tracks how its macro environment differs from the previous pass's at the same
point (`EnvDelta`, at most 64 bindings, by content and definition site) and adopts a subtree whose other incoming state is
equal and whose tested names are outside the delta, with the delta applied to the environment of every copied segment,
to its outgoing state and to its carried records (`DirectivePass::carried_delta`, `MacroEnvironment::apply` /
`delta_from`). A rebased region is not mapped to the previous one, so its expansion is proven again by the macros it
reads (the expansion memo). Tests: `manifest_changes_renumber_adopted_subtrees_or_decline_them` (a manifest `#define` edit
now adopts the three subtrees that do not read it) and `a_define_edit_reruns_only_the_subtrees_whose_directives_read_it`,
both comparing every plan and expansion with a full pass.

Measured, production tree, `BAD_INIT_SLEPT` (defined in `code/__defines/_atoms.dm`, read only in two bodies) edited twice
per round, interleaved against the published compiler: subtrees adopted 10 -> 5872 (state declines 5944 -> 0); the
request was already a body-level patch on both (4.6-7.9 s against 5.3-6.3 s, frontend 0.9-1.5 s on both): 5917 regions
are still expanded again (memo-verified), which is where the frontend time of such an edit goes. `dmb-equiv` of the
output after the edits against a fresh compile: EQUIVALENT, two rounds.

**Rebased regions keep their expansion (compiler/test-increment-2).** `PlanReuse::rebased_regions` names, for every region
of a rebased subtree, the previous region and the macro names whose bindings differ; `expand_regions_reusing` copies the
previous expansion when its recorded macro reads (`ExpansionRecord::reads`, which include names read while absent) name
none of them. Same measurement: regions expanded again 5917 -> 30-32 (13174 reused); frontend of the edit 1.0-1.1 s in the
quieter round against 2.1-2.3 s for the previous slice (the other round was loaded on both sides). Test
`a_new_macro_used_in_adopted_text_expands_that_text_again`. `dmb-equiv` against a fresh compile: EQUIVALENT, two rounds.

**Tried and taken out: starting a new define variant from the active variant's frontend.** `switch_variant` seeded the
test world's semantic state with the game world's last frontend, and the ordered pass adopted 4660 of its include subtrees
(rebased) with 11572 regions' expansions reused. Measured (production tree, game then test world in one daemon, interleaved
against the published compiler, `dmb-equiv` EQUIVALENT against a fresh test-world compile): the test world's frontend took
7.4 s against 6.0 s (14.0 against 9.5 in a loaded round) and the memory probe showed +3.18 GB for the test world against
+3.04 GB: the rebased segment environments cost 226 MB (+182) where the shared regions saved about 150 MB, and the disk
expansion memo already answers a fresh test world's regions. Kept from it: `DirectivePlan::defines` (a plan of other
defines is never a base for the changed-files patch) and the per-pass cache of rebased environments (consecutive segments
share one), which `#define` edits use. Seeding needs environments rebased as an overlay (a binding delta over a shared
map) instead of materialized maps before it pays.

**Initializer, map and modified-instance code is `DEBUG`-independent (same lane).** Their lowering always emits
`DbgFile`/`DbgLine` (`initializer_lowering`, `map_artifacts`, `modified_initializers`: `ops: true`) and a build without
`DEBUG` strips them when the words are wired (`symbolic::debug_strip`, as for procedure bodies); the initializer disk
transport is keyed by the facts policy (`BuildHost::procedure_memo` takes it), so the game and test worlds share those
records. Checked against the compiler before the change: 416 fixture compiles (`fixtures/*.dme`, `lowering/`, `native/`,
`native_compiler/`, each with and without `-DDEBUG`, `--no-daemon --no-cache`) produced identical `.dmb` bytes.

Next: measure the test variant with both changes (memory probe, warm test build after a game build) and share the
per-variant owners the probe names by content.
