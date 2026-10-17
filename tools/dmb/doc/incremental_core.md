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

## Coordination and risks

- The memory lane owns `SessionKey`, `BuildHost` keying and the budget. The session becomes the `Db`: eviction is by query kind,
  recomputable values first, inputs last. A defines change must not discard the `Db`, only redden the macro reads. Interface: it keeps
  `SessionKey` free of declarations; I add `Db` as a field and ask it for an eviction hook per query kind.
- Frontend (4-6 s) and resources (2.4 s) are whole-program per request until step 6 and bound the floor near 9 s; the floor is not
  permanent.
- Risk: the dependency wrapper must see every read. The existing `RecordingResolver` already gates lowering; the same gate must
  cover initializers and class layout. `DMB_QUERY_VERIFY=1` recomputes green queries and compares, as `DMB_DOMAIN_CACHE_VERIFY` does.
