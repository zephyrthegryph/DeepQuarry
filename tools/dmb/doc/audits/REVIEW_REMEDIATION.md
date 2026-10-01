# Review remediation status

This records the cleanup prompted by the September 2026 `tools/dmb` review. The workspace remains a compiler prototype. The user explicitly allowed bytecode output to change during structural work.

## Addressed

- Opcode constants are generated from `src/opcodes.txt` by `build.rs`; branch classification is shared by the decoder, comparison tool and lowerer.
- `od_emit` build phases live in separate resource, class, instance, procedure, world, global and map modules. CLI commands are split into OpenDream, DMB and RSC modules.
- The large inline lowerer, emitter and translator test modules were moved to separate test source files. A shared fixture loader is used by eight integration tests; a shared mock resolver has begun replacing local implementations.
- Baseline type paths are indexed once; closed-span relocation snapshots only relevant offsets; list compaction avoids a second copy; resources have reusable indexed lookup/attachment APIs.
- Lowering groups pending state and try frames, and extracts stack, pick, constant and packed-switch families. Error kinds are machine-readable alongside messages.
- DMB writes validate cross-table references. RSC entry reads are bounded and stream payload bytes. Baseline byte reads are checked. The daemon recovers from a poisoned session-index mutex.
- Fixture DMB/RSC files are visible to Git despite the repository-wide ignore rule. Investigation reports, scripts and inactive OpenDream patches are separated from current reference docs and active patches.

## Still evolving

- The main lowerer remains large. The extracted families establish a pattern for moving its other opcode families out of the central match.
- Raw `u32` fields remain in the lossless DMB wire representation. Typed table IDs and the shared absent sentinel are available at the public lookup layer; broad conversion of every serialized field is not complete.
- Many lowerer tests still declare local symbol resolvers. The shared `MockResolver` and integration fixture loader cover common cases but have not replaced all historical mocks.
- Some `Variable` chains are cloned while rewriting receiver caches. This is a smaller performance concern than the former full offset-map clones.
- Error kinds classify common lowerer failures; detailed error codes for every emitter and lowering case are not complete.
- The development scripts remain runnable as explicit Cargo examples; only the workflows already represented by `dmb-inspect` were promoted to CLI commands.

Focused checks cover formatting, all workspace targets, the direct codegen crates, CLI parsing, archive validation, selected translation fixtures, and daemon lock recovery. The full `byond-dmb` library test harness was not run during this prototype pass because compiling it exceeded 5 GB of memory.
