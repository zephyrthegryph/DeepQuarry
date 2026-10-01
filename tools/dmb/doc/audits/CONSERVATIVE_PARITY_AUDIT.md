# Conservative bytecode pattern audit

`dev-scripts/conservative_pattern_audit.rs` supplements the strict parity report.
It never changes the production translator or comparer. A procedure is classified
only when its **entire body** compares equal after the bounded rewrites below,
including resolved cross-table identities and relocated control-flow targets.

| Rewrite | Required proof conditions |
|---|---|
| `SetVar local/arg; GetVar same local/arg` → `SetVarExpr` | Same complete reference; no branch enters the reload; excludes fields, globals, and cache references. |
| `GetFlag; Pop` → nothing | Adjacent executable instructions; neither instruction is a branch entry; stack and flag state are preserved. |
| Catch-local null initialization → direct exception assignment | Immediately overwritten local/argument with the same reference; no branch enters either assignment; immediately follows the Catch boundary. |

Debug markers are ignored. Branches are relocated to instruction boundaries.
Switches and other unsupported multi-target layouts are excluded. Interior operand
targets, incoming common-Pop branches, and property/cache references are rejected
by the audit rather than guessed equivalent. Other instructions and operands remain
subject to the unchanged strict comparer.

Run:

```text
cargo run --example conservative_pattern_audit -- NATIVE.dmb ACTUAL.dmb PARITY.ndjson OUTPUT.ndjson
cargo test --example conservative_pattern_audit
```

## Current full-game result

For `current-parity.ndjson` and `deepquarry-complete.dmb` on 2026-09-28:

- 29,382 mixed procedure pairs inspected.
- **892 additional complete bodies classified equivalent.**
- 882 procedures use the local/argument store-reload rewrite.
- 11 use discarded flag materialization; one also uses store-reload.
- No complete body was classified solely through the Catch-local rule.

The per-procedure evidence is in
`D:/opendream-diagnostic/current-conservative-patterns.ndjson`.
Five portable tests cover successful rewrites and refused common-Pop, incoming
reload, field/cache, and unprotected null-initialization cases. These results do
not establish equivalence for the remaining mixed procedures.

`fixtures/lowering/flow_stack_patterns` includes native DreamMaker and OpenDream
outputs for all three rules. The paired regression first confirms that the strict
comparer observes a real native layout difference, then translates the fixture
with debug lines and proves complete-body equality after these bounded rewrites.
Both compilers accepted the fixture with zero errors and warnings.
