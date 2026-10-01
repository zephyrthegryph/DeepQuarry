# Native compiler workspace prototype

This workspace is an executable slice of the [incremental compiler plan](INCREMENTAL_COMPILER_PLAN.md). It now emits native bytecode for a small, checked subset of DM global procedures and can append those procedures to a checked-in builtins DMB. It is **not yet a full DM-to-DMB compiler**: types, maps, resources, many expressions and runtime features remain incomplete. Unsupported syntax fails explicitly.

## Crate boundaries

| Crate | Current implementation | Next integration boundary |
| --- | --- | --- |
| `byond-dmb` | Existing BYOND 516 DMB/RSC codec, native instruction decoder, OpenDream adapter and comparison tools. | Direct codegen consumes its typed codec; the OpenDream adapter remains an oracle. |
| `dm-syntax` | Source-preserving lexer, expression and structured statement ASTs, spans, diagnostics. | Full DM grammar and source-origin propagation. |
| `dm-preprocess` | Ordered DME includes, object/function macros, integer conditionals, line continuations, dependency/origin map. | Remaining directive/stringification grammar and per-include incremental state. |
| `dm-ir` | Typed IDs, canonical paths, HIR/MIR data model, CFG verifier. | Typed lowering from syntax and VM-specific effect checks. |
| `dm-semantics` | Ordered declaration ledger, implicit ancestors, inheritance and override lookup. | Full resolution, defaults, globals, verbs and builtin schema. |
| `dm-compiler` | Salsa 0.28.5 per-file inputs, live project/include queries, semantic index, and direct global-proc bootstrap emission. | Per-proc HIR/MIR/codegen queries and complete DMB table writer. |
| `dm-codegen-byond` | Deterministic symbols, compound operand relocation, basic expression/statement lowering and native decoder checks. | Complete opcode selection and VM semantic validation. |
| `dm-output` | Indexed layouts, streaming equal-length patch planning, DMB/RSC pair validation, journaled patch recovery. | Indexed serializer, region rebuilds and generation publication. |
| `dm-compiled` | Long-lived loopback service, isolated worktree project sessions, source CAS, shared check artifacts and idle eviction. | Watcher, scheduler, named-pipe IPC and full derived-artifact cache. |
| `dm-compile` | Local and daemon project checks; bootstrap replacement and direct global-proc emission commands. | Full `build`, watch, diagnostics protocol and build-system integration. |

The parser-to-semantics bridge currently indexes only unambiguous declaration shapes and returns errors for unsupported ones. Live project sessions hold persistent per-file Salsa inputs; preprocessing still runs as one project query after a relevant change. The daemon shares content-keyed check artifacts across worktrees, while semantic query state remains isolated per worktree. These are explicit prototype limits, not promised full-project incremental performance.

The paired [simple DM fixture](fixtures/native_compiler/simple.dm) has three Rust-emitted procedures. Their native bytecode matches DreamMaker 516.1687 after string IDs are resolved. `dmb-compare` reports no decoded semantic discrepancies between the direct Rust output and native fixture. The direct output also opened in trusted DreamDaemon on a small test port. Changing `return 7` to `return 8` in the exclusive output patched one byte in place, and the opcode audit still decoded all 70 procedures. This exercises a narrow global-procedure subset; it does not prove broad language or runtime parity.

## Try it

From `tools/dmb`:

```text
cargo test -p dm-syntax -p dm-preprocess -p dm-ir -p dm-semantics -p dm-compiler -p dm-codegen-byond -p dm-output -p dm-compiled --lib
cargo run -p dm-compile -- check path/to/example.dm
cargo run -p dm-compiled -- 47616 path/to/cache
cargo run -p dm-compile -- check-daemon 127.0.0.1:47616 path/to/example.dm
cargo run -p dm-compile -- check-project-daemon 127.0.0.1:47616 path/to/project.dme
cargo run -p dm-compile -- emit-global-procs fixtures/native_compiler/simple.dm fixtures/native_template.bin target/simple-direct.dmb
cargo run -p dm-compile -- patch-global-procs target/simple.dm fixtures/native_template.bin target/simple-direct.dmb target/simple-direct.rsc --exclusive
```

The daemon prototype accepts JSON requests over loopback TCP. It runs one request at a time and checks individual files or complete `.dme` include closures. It refreshes include changes per request. The production transport and concurrent scheduler remain to be built. `patch-global-procs` requires an exclusive, stopped-server output pair and an existing empty `.rsc` for the current fixture; it refuses layout-changing edits and journals a fixed-span patch.

## Next executable milestone

The small global-proc fixture now lowers to a bootable DMB. Next, emit its procedure and string tables without the builtins DMB image, then add class/var metadata, maps, and resources directly. Add paired fixtures for each feature and wire the structured statement AST through HIR/MIR rather than lowering from header text. Extend Salsa to per-proc body queries and cache only pure artifacts with complete dependency fingerprints. Do not wire this into `bin/build.cmd` until it compiles the project's required DM features and reports unsupported syntax reliably.
