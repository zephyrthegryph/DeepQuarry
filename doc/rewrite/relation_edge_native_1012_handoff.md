# Native relation-edge requirements handoff

Branch: `codex/relation-edge-native-1012`. Tested and lane-ready stamped commit: `a3a798b8f3`, against master `f774599da2`. A documentation-only child carries this stamp under workflow section 14.

## Change

Conditional relation edges now use a pooled, datum-endpoint query context and generated native dependency descriptors. Source, target, holder and declared third-party relation hops bind actual registered state keys. Replacement, deletion and unlink release and rebind the real weak subscriptions; predicates return null or a refusal reason and remain pure. The legacy `edge_refresh` scheduler registration is removed (one registration to zero). There were no production conditional edge predicates to migrate. Broader relation forwarding and other channels remain separate work.

The analyzer rejects untracked or unproven inputs, volatile/effectful callbacks, hand-written `PROC_SUMMARY` bypasses and traversal-depth exhaustion. Generation and semantic linting both inspect virtual overrides. Missing generated descriptors fail closed. No baseline increase, new exemption or debt `ALLOW` was added.

## Verification

The exact-commit lane-ready run passed: 53 tests, zero failures. Its list includes `dq_relation_edge_native/*` (11 cases), `dq_requirement_protocol_pin`, `dq_conversion_pin`, and the gate's smoke, gameplay and incremental appearance pins. Production DreamMaker reported zero errors; DreamChecker reported zero diagnostics. Ratchets and analyzer passed. Targeted analyzer tests (`cargo test -p dq-analyze --lib endpoint_`, dev-fast, two jobs) passed both fixtures. No full suite was run.

The endpoint cases cover activation/refusal, atomic snapshots, replacement/rebinding, endpoint and third-party deletion, multiple producer delivery, pooled context faults, absent descriptors, composition, setup rollback and initial hold refusal. Publication counter fixtures observe the real edge key and settle the existing native/RX boundary with exactly two drains; no manual publication or engine phase change was introduced.

## Pins and boundaries

Five conversion pin files remove only 57 expanded inert Graffiti menu rows introduced by master before its `54ee97e79a` held-engraving requirement fix. Each class/count and that cause commit are recorded in `intended_changes.md`. The final conversion pin passed. No unrelated click/refusal rows were blessed.

Generic movement/ancestry dependencies and computed cross-object on-change getters remain separate framework gaps, documented in `relation_edge_native_1012.md`. This landing does not claim their repair or global channel retirement.
