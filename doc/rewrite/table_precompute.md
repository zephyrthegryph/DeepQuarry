# Precomputing the per-type tables (boot-speed item 4)

Measured 2026-10-13 on boot-speed/keys (`DQ_WORLD_PARAMS=boot_profile=1 tools/dq_focused_test.sh --boot`, profiled, so about 1.35x real).
Atoms boot 51.9 s. `build_own_table` 15.8 s over 3,721 types, of which `table_of`/`table_build` 10.3 s; `table_compile` 8.6 s over 569 blocks, of
which `table_validate` 6.9 s (`op_index_build` 4.7 s, the O(n^2) op clash check about 2 s).

## What is computed, from what

- A `/datum/type_table` per CAPABILITIES block (569) is `table_compile(parent, entries)`: apply entries, expand each capability through
  `def.entries()` (a runtime proc), validate, derive hook flags. Per instance type (3,715) `table_build` only picks the block tables.
- A `/datum/own_table` per instance type (3,721) is `build_own_table`: `caps_of(D)`, the `ownership()`/`relations()` procs, the table's relation
  entries, `D.vars`, link patches, then validation.

## What the analyzer can know statically, and what it cannot

Static: the block structure, file:line, entry kinds and literal arguments. Runtime only: entries are interned datums created by DM constructors
(`entry_make`, signature strings over args that include `PROC_REF`/closure handles and `initial()` of computed vars), capability definitions
come from `entries()` procs, `ownership()`/`relations()`/`caps_build()` are procs, and the tables hold those datums by identity (interning is
what makes `a == b` mean "same declaration" everywhere). Building also registers `keyed_target_register`, `link_register` and patches already
built tables, `capability_info`, `acceptance_compile`, and runs validators that must still fail a test run.

## Option A: full precompute in `analyze gen`

Emit DM that constructs the interned entries with stable keys and replays the registrations. Not feasible from the Rust analyzer: it would have to
re-implement the evaluation of every entry constructor, `def.entries()`, `initial()`/`D.vars` and the `ownership()` procs, so gen's output would
be a second implementation of the table builder, and a divergence would be silent (hand-written staleness guard or not). Replaying the
registrations in generated code is also order dependent (link patches against tables built so far). Dumping a snapshot from a running world
instead is not "analyze gen" and needs a boot to produce a boot input. Effort: weeks. Saving: at most the 15.8 s (profiled), with the highest risk
in the codebase's declaration layer. Rejected.

## Option B1: build lazily per type, only for types a world touches

Already the case: tables build on first lookup. The 3,715 types are not a sweep, they are the types the map and `starts =` really instantiate
(36.7k atoms initialize). `own_validate_boot` only visits types already in the world. A focused world does not touch fewer types. Saving about 0;
rejected (and it would move validators out of the boot).

## Option B2: cheaper second pass (recommended, implemented)

Make the remaining per-type and per-block work cheaper without changing a result:

1. Cache `table_own_entries(T)` per type table (it is a pure function of the table; 3,715 types share 569 tables). The
   `keyed_target_register` side effect is idempotent and has already run the first time.
2. Cache the table's owns-scan (the OWNS entries the end of `build_own_table` loops over) and the table's hook flags once stat definitions are
   built (the flags read `GLOB.stat_defs`, so an early value is not cached).
3. `op_validate_table`: compare only ops that share a binding (bucketed by kind and input) instead of every pair, reporting in the same order.

Expected saving: about 4 to 6 s profiled (3 to 4 s real) of a 50 s boot. Risk low: all cached values are read-only, derived from an immutable
table, and each change has an equality test that runs the original computation and compares (the staleness guard of the task, in the shape that
is safe here): every compiled table's cached values against a fresh computation, and the bucketed clash pairs against the naive pairs, over
every table the test world has built.

## Conclusion

Precomputing the tables is infeasible and unsafe as asked (A) and pointless as laziness (B1). The measurable remaining win is B2, small and
provable. Further big wins are not in the table builders: they are per-instance (`caps_init` 13.0 s, `engine_holder_init` 11.3 s, `rel_set`
8.2 s, `static_entries_build` 8.0 s), which is a different item.
