# Native incremental DM compiler plan

This is the original prototype plan. The current performance and architecture
proposal is [ARCHITECTURE.md](ARCHITECTURE.md), based on the implemented compiler
and measured costs as of October 1, 2026. Use it for the next incremental,
parallel, shared-tooling, cache and output-patching work.

The first Rust workspace prototype is implemented; see [COMPILER_PROTOTYPE.md](COMPILER_PROTOTYPE.md) for crate boundaries, commands, and current limits. Full DM language lowering and direct DMB/RSC emission remain future milestones.

## Goal and boundary

Build a Rust compiler that reads a `.dme` project and DM sources, produces BYOND 516 `.dmb` and `.rsc` files, and recompiles only affected semantic units after edits. It must run without Dream Maker or OpenDream at compile time. The existing `byond-dmb` crate remains the format, instruction, and resource codec. The existing OpenDream translator remains a differential oracle during migration; its bytecode is not an intermediate representation for the new compiler.

Pin the first target to the BYOND 516.1687 dialect used by current probes. Treat other BYOND versions as explicit targets with separate schemas and conformance fixtures. A successful file round trip is only format coverage, not compiler correctness.

## Workspace and public interface

Convert `tools/dmb` into a Cargo workspace while retaining the existing `byond-dmb` library and `dmb-inspect` tool. Add:

| Crate | Responsibility |
| --- | --- |
| `dm-syntax` | Lossless lexer/parser, spans, DM source and map/skin syntax where applicable. No Salsa dependency. |
| `dm-preprocess` | DME order, includes, macros, conditionals, line mapping, preprocessing diagnostics. |
| `dm-semantics` | Declaration index, builtins, inheritance, constants, name/path resolution, type and proc metadata. |
| `dm-ir` | Typed HIR, effectful control-flow MIR, symbolic native instruction IR and verification. |
| `dm-codegen-byond` | Native opcode selection, table planning, DMB/RSC linking, maps and resources using `byond-dmb`. |
| `dm-output` | Indexed binary layout, safe patch planning, output generations, and archive compaction. |
| `dm-compiler` | Salsa database, incremental queries, diagnostics, driver API. |
| `dm-compiled` | Long-lived local daemon: worktree sessions, file watchers, shared artifact cache, build scheduling and IPC. |
| `dm-compile` | CLI: `build`, `check`, `watch`, `explain-rebuild`, `compare-native`, `daemon`, `cache`. |

Start with a library API such as `Compiler::load(project, target)`, `update_file(path, bytes)`, `check()`, and `build(output_dir)`. The CLI connects to a local daemon by default and can fall back to a one-shot in-process build. The CLI must produce deterministic output from a clean invocation and from any edit sequence leading to the same sources. Keep Dream Maker output comparison as a separate developer command.

## Salsa model

Use an exact, locked Salsa version after a small API spike. The current documented API has `#[salsa::input]`, `#[salsa::interned]`, `#[salsa::tracked]` and diagnostic accumulators. The local `rustc 1.96.0` meets the current crate's minimum Rust version. Keep syntax/IR types independent of Salsa so they can be unit tested without a database.

| Entity | Representation | Reason |
| --- | --- | --- |
| Source file and content, project manifest, target flags, builtin schema, resource bytes | Salsa inputs with persistent file identity | These are the only mutable roots. Compare hashes before calling setters; Salsa setters mark a field changed even when bytes are equal. |
| Canonical path, symbol, type path, proc lookup key | Interned value | Equal names share identity within one database. Never use interner allocation order as DMB IDs. |
| Parsed declarations, class/proc bodies | Tracked entities keyed by a stable semantic owner and source ordinal | Independent body edits retain unrelated query results. Reacquire handles after every revision. |
| Lex, preprocess, parse, declarations, resolve, HIR, MIR, symbolic code, map parse | Tracked queries | Each dependency is a real read, so invalidation can stop at unchanged results. |
| Diagnostics | Accumulators or a query result containing diagnostics | Recomputed query diagnostics replace stale diagnostics. Fatal errors block emission. |

Use LOW durability for editable source/resources, MEDIUM for project options, HIGH for immutable target/builtin schema. Do not mark files or configuration as never-changing. Track rebuild reasons through Salsa events plus a compiler-owned query trace; `explain-rebuild` must show why a proc was recompiled.

### Query graph

```text
project inputs + source inputs + target schema
  -> DME/include order + preprocessing state
  -> syntax trees + source spans
  -> ordered declaration ledger
  -> class/global/proc indexes + inheritance + constant/default values
  -> per-proc HIR -> per-proc MIR -> symbolic native instructions
  -> map/resource graph + initializer plan
  -> deterministic global table layout and symbol relocation
  -> output layout + patch plan -> DMB/RSC generation + diagnostics
```

Preprocessing needs special care. A macro definition can affect later includes; DME order is observable. Represent each include occurrence with its incoming macro-state fingerprint, and cache an outgoing state and expanded token stream. Maintain prefix checkpoints so an edit can reuse unaffected suffixes when the outgoing state and tokens converge. Do not claim that all files are independently incremental: an early macro edit may legitimately invalidate the whole project. Include graph changes, include cycles, `#if` configuration, and source location mapping must be first-class dependencies.

Declarations need two identities. A semantic key (path, member name, declaration kind, override occurrence/order) supports lookup and stable reuse; a separate ordered ledger controls BYOND allocation and last-definition-wins behavior. Source offsets alone are too fragile as identity after inserted lines. When declaration order changes, replan table IDs; cached per-proc code must hold symbolic references and be relocated at link time. This separates local recompilation from global ID assignment. Preserve the observed order of class creation, `typesof()` enumeration, proc/verb registration, initializer execution, and resource imports.

## Language and backend semantics

1. Implement a lossless DM lexer and error-recovering parser, including indentation, path declarations/reopening, proc definitions, `set` statements, strings/interpolation, resource literals, and macros. Parse map `.dmm` and interface `.dmf` inputs when referenced; report unsupported constructs with spans rather than silently substituting behavior.
2. Load a versioned builtins/ABI schema from checked-in evidence: native types/procs/vars, opcodes, operand tags, flags, reserved IDs, value representation, call conventions, and target-specific world defaults. The compiler may use a checked-in *data schema* at bootstrap, but must not copy a native project DMB or invoke Dream Maker during builds. Keep source and version provenance with each schema field and paired fixture.
3. Resolve type paths, inheritance, variables, proc overrides, globals, const/default expressions, compile-time versus runtime initialization, verbs, argument metadata, `..()` and dynamic calls. Preserve DM's null, truth, number, list, and string semantics explicitly in HIR rather than assuming Rust semantics.
4. Lower each proc to MIR with explicit evaluation order, stack effects, side effects, lvalue evaluation/capture, labels, exception and iterator edges, suspension (`sleep`/`spawn`), and source spans. Model `usr`, `src`, `args`, field caches, constructor calls, indexed assignments, and cleanup paths. Verify control-flow/stack invariants before opcode selection.
5. Select native instructions into symbolic code, then relocate string, class, proc, variable, resource, list, and branch references after deterministic table planning. Verify native opcode widths, stack/cache lifetime, branch destinations, reserved slots, wide IDs and all typed references. Emit through `byond-dmb`; construct RSC from the exact ordered resource graph.
6. Treat map placement and resource packaging as compiler outputs, not sidecar copies. Resource bytes and DMI metadata are inputs. Record output dependencies so a changed icon need not recompile unrelated proc bodies, though it may require RSC and resource-table relinking.

The current `od_lower.rs` and `od_emit.rs` are useful catalogs of paired semantic discoveries, but their OpenDream-JSON-specific heuristics must be converted into language rules, IR tests, and native codegen tests. The previous translator's full-game metadata parity is a regression oracle, not evidence that a direct front end inherits that coverage.

## Incrementality and determinism contract

- A body-only edit should reparse its affected preprocessing unit, rebuild that proc's HIR/MIR/code, and relink; unrelated proc body queries should be reused. Measure this with execution counters, not only elapsed time.
- A public declaration, constant, macro, inheritance, project-order, or builtin-schema edit invalidates the queries that actually depend on it. Broad invalidation is acceptable when semantics genuinely change.
- A resource-only edit updates the archive and dependent metadata; untouched proc code is reused unless it embeds affected resource data or IDs.
- The final table-layout decision is global, but the output writer must reuse unchanged serialized regions and patch eligible regions. See the binary-patching design below.
- The compiler must produce identical bytes for the same input snapshot, regardless of query evaluation order, thread scheduling, or edit history. Assign all serialized IDs from the ordered ledger in one deterministic phase, never from hash-map or Salsa intern order.
- Keep memory bounded for a full DeepQuarry build. Measure query retention, use narrow keys and owned results, and add LRU eviction only for proven large low-reuse queries. A persistent content-addressed disk cache is required for cross-worktree reuse; Salsa remains the live, per-session dependency engine.

## Binary patching and output generations

The DMB is a sequential container with variable-length tables. Strings are encoded using their absolute position and a table checksum. RSC entries are length-prefixed and already have observed obsolete-entry/capacity behavior. These constraints rule out a blanket promise that any changed proc or asset can be overwritten in place. Implement an indexed writer with three explicit strategies:

1. **Fixed-span patch:** When a replacement serializes to exactly the previous length and all enclosing counts, IDs, offsets, checksums and dependent records remain valid, write only changed spans. For example, a same-length proc code-list update may qualify after dependency analysis. Recompute and patch any affected checksum/header fields. The planner must prove eligibility, not infer it from edit category alone.
2. **Tail/region rebuild:** When a record changes length, retain the unchanged prefix and serialize the affected suffix or table region into a new output generation. Reuse unchanged serialized bytes where position independence has been proved; re-encode position-dependent strings when their offsets move. This avoids recomputing all semantic objects even if many file bytes must be copied.
3. **Full rebuild/compaction:** Changes to table widths, global ordering/IDs, string layout, map dimensions, or accumulated RSC tombstones may make a full compact output cheaper or necessary. A full rebuild is an expected correctness path, not a patching failure.

Record a sidecar layout index per output generation: target/compiler/input hashes, section and record spans, serialized hashes, relocation dependencies, checksums, and the DMB/RSC pair identity. It is a compiler cache, never part of the BYOND files. The planner compares old and new symbolic layouts, chooses the cheapest valid strategy by estimated bytes written and elapsed cost, and can report `patch`, `tail rebuild`, or `full rebuild` with reasons. Cache serialized proc/list/resource records by content and target so worktrees can reuse them.

Never patch a DMB/RSC pair while a server may be reading it. Use a worktree-specific output directory and generation manifest. For a stopped, exclusive-owner output, the fixed-span path may update the existing files directly with a small write-ahead undo journal: record old spans and hashes, flush the journal, apply and flush both files, validate, then commit the manifest. Recover or roll back an interrupted transaction before any reader opens the pair. This is the path that avoids copying the whole DMB. When a server holds a generation lease, stage a new pair, using a filesystem copy-on-write clone if available and validated; otherwise copy unchanged bytes into new files. Verify the new pair with the existing DMB/RSC reader and reference/bytecode validators, flush, and atomically switch the generation manifest. A launcher resolves that manifest to a matching pair; if a fixed launch path is required, use a versioned directory selected before server startup. Retain the previous generation for rollback; garbage-collect it only after no build or server lease uses it. A server already running an old generation is not hot patched; it needs a restart to load new bytecode.

For RSC, first support changed-entry serialization plus copy-on-write reuse of unchanged entry spans. Then test an append/obsolete-entry strategy against DreamDaemon and native archive behavior before enabling it. Track fragmentation and compact on a measured threshold. Resource identity and archive order must remain semantically correct; hash equality alone does not justify deduplicating entries with distinct names/kinds.

Required patch tests: same-size and length-changing proc edits, string insertion before/after other strings, resource resize, class/ID reorder, wide-ID boundary, interrupted writes, stale index, simultaneous server read, and randomized edit sequences. Every patched generation must byte-compare with a clean deterministic build from the same inputs, then pass static validation. If clean and patched bytes legitimately differ because of an enabled append archive policy, require decoded semantic equivalence and runtime tests, and expose that mode explicitly.

## Long-lived daemon and many worktrees

Run one `dm-compiled` process per user/machine and target toolchain, reached over a local named pipe on Windows (Unix socket elsewhere). The daemon owns watchers, scheduling, a content-addressed disk store and one Salsa database per active compilation session. A session key includes canonical worktree root, `.dme` path, target BYOND schema, defines, compiler version and build mode. Two worktrees may share source blobs and pure derived artifacts but never share mutable Salsa inputs, diagnostics, declaration order, output IDs or build outputs. This prevents one worktree's edits from changing another's result.

Discover worktrees by their canonical root, not branch name. Hash file contents rather than mtimes; use watchers only as a hint, rescan and hash before a build to recover missed, coalesced, or rename events. Track files outside the worktree reached through `FILE_DIR` or includes as explicit dependencies. Git object IDs may speed identification of identical tracked files, but uncommitted/ignored files and generated `icons/gen` assets must be hashed from disk. Normalize paths carefully on Windows without conflating distinct source spellings that affect archive names or diagnostics.

Put reusable outputs of **pure** stages in a shared content-addressed store: lexed/parsed source by content plus lexical mode; preprocessing by content plus incoming macro environment/defines/include identity; HIR/MIR and symbolic code by all semantic dependencies and target schema; resource bytes by content; optional serialized records by layout/relocation fingerprint. A raw source hash alone cannot key resolved code, because another file may change a referenced declaration. Keep a per-session Salsa database to maintain the exact dependency graph and warm results; on a cold session, hydrate safe artifacts from the shared store. Do not serialize Salsa intern IDs or tracked handles into shared artifacts. Use portable semantic keys and re-intern on load.

Deduplicate concurrent identical cache computations across sessions, prioritize interactive checks over full links, and cap CPU, memory and disk use. Sessions are isolated for cancellation: one worktree's new edit cancels its stale build without cancelling another worktree. Lock outputs per session and publish only complete generations. Add idle-session eviction and disk-cache size/age quotas, with reference-counted active generations. The protocol reports progress, cache hits, patch strategy, diagnostics and timings; `dm-compile daemon status`, `cache stats`, and `explain-rebuild` make reuse inspectable. A daemon crash must leave previous generations valid; the CLI can rebuild in-process.

Cross-worktree acceptance requires at least two concurrent worktrees with overlapping sources and divergent edits. Prove no diagnostic or output contamination, record shared cache hits, show the second worktree avoids recomputing identical pure stages, and verify each output against its own clean build. Benchmark cold daemon, warm same-worktree, first build in a sibling worktree, body edit, resource edit, macro edit, and output publication separately. Set performance targets from those measurements rather than assuming every edit can avoid a large DMB copy.

## Implementation sequence and exit gates

| Stage | Work | Required gate |
| --- | --- | --- |
| 0. Evidence baseline | Freeze representative native 516 fixtures, current DeepQuarry source/options, builtin schema provenance, opcode/metadata diffs, and runtime results. | Reproduce format read/write and current translator comparisons. Explicitly retain the 14 native-pass/translated-fail cases as unresolved, not accepted behavior. |
| 1. Salsa spike | Create workspace, database, file update API, trace, cancellation, diagnostic invalidation, and deterministic query harness. | Edit/revert tests prove result reuse, stale diagnostic removal, and identical clean/incremental builds. |
| 2. Front end | DME/preprocessor, parser, ordered declaration ledger, builtins, resolution, constant/default semantics. | Differential fixture corpus agrees with Dream Maker diagnostics and class/proc/var metadata; broad DeepQuarry source parses with no unclassified syntax. |
| 3. Direct backend | HIR/MIR, symbolic native codegen, linker, initializer, map and RSC emission. Implement features in evidence-driven slices. | Every supported construct has a native paired fixture and a bytecode verifier check; no OpenDream bytecode is used. |
| 4. Whole-project parity | Compile DeepQuarry with the native Rust pipeline and compare against same-source Dream Maker output. | Zero unclassified metadata, map, resource, initializer, or opcode-semantic differences; all emitted refs and control-flow paths validate. Byte-for-byte proc equivalence is useful evidence but not required when runtime-equivalent encodings differ. |
| 5. Runtime and integration | Trusted paired boots, focused tests, full DM suite, longer server scenario, CLI build integration. | New compiler matches native test outcomes on the frozen source (including native failures), with no translated-only runtime errors; then pass the project's normal CI gates on the current tree. Recheck ordering-sensitive tests in isolation and suite order. |
| 6. Indexed outputs | Build layout index, fixed-span patch planner, region rebuilds, immutable generations, and RSC strategy. | Patch eligibility is proven; every generation validates and matches a clean build under the selected output policy; crash/interruption preserves the previous pair. |
| 7. Shared daemon | Add IPC, watchers, per-worktree Salsa sessions, shared pure-artifact store, scheduling, leases and eviction. | Concurrent worktree builds stay isolated, reuse identical work, survive missed events and daemon restart, and meet measured latency/cache targets. |

Stage gates are sequential for release claims, but fixture work, syntax coverage, target schema, and backend instruction families can be developed concurrently. Generate paired minimal fixtures from Dream Maker in development/CI where licensed; check in normalized expected data so ordinary compiler builds have no Dream Maker dependency. Keep the frozen source baseline separate from the changing main checkout.

## Risks to manage explicitly

- **Incomplete language or native ABI evidence:** Maintain a versioned coverage matrix with `implemented`, `probed`, and `unknown` states. Unknown constructs are errors. A template copied from native output cannot count as direct compilation.
- **False incrementality:** Whole-project preprocessing and ordered table allocation are legitimate global boundaries. Query traces and edit tests must show actual reuse, and the plan must accept broad invalidation after macro or declaration-order changes.
- **Runtime sensitivity to order:** Current paired suite changes some results when test/type order changes. Compare class/type order and run focused tests before labeling a body-diff as harmless.
- **Semantic drift in codegen:** The existing translator already has broad static coverage while full runtime parity is incomplete. Require paired native fixtures, verifier checks, and trusted execution for language features with side effects, caching, suspension, or initialization.
- **BYOND version drift:** Reject unsupported target versions; version the schema, golden fixtures, and compatibility checks together.
- **Unsafe binary mutation:** Variable-length records, position-encoded strings, and live file readers make general in-place writes unsound. Patch only private generations after a layout proof; publish verified DMB/RSC pairs atomically.
- **Incorrect cross-worktree cache hits:** Cache keys must include macro context and transitive semantic dependencies, not just file bytes. Isolation and clean-build equivalence tests cover divergent worktrees.

## First concrete milestone

Create the workspace and Salsa database, implement DME/include preprocessing plus ordered declaration indexing for a small native fixture set, and expose `dm-compile check` with source diagnostics and `explain-rebuild`. This gives a testable incremental spine before bytecode codegen. The first `.dmb` milestone is a no-map world with literals, types, globals, one proc, inheritance, and a resource, emitted directly through `byond-dmb` and booted in DreamDaemon.
