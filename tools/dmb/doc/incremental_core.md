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
2. Re-evaluate only initializers whose recorded reads include a changed answer; splice their rows and the Variables
   records through the same `retained_output` splice used for bodies.
3. Measure the default edit on this path; when it is at or below the patch's wall, delete `try_default_patch`,
   `reads_initial`, `DefaultEdits` in `dm-tree` and the test's patch-count assertion.
4. Same for appended callables (new link entries append), then delete `declaration_patch*.rs`.
5. Frontend queries (`file_decls`, `type_node`) and resources as queries lower the shared 9-11 s floor.
