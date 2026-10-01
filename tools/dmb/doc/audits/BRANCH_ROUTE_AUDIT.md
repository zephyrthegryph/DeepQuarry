# Bounded branch route audit

Read-only classification of the 2026-09-28 `final-parity.ndjson` snapshot found
75 branch/switch-only procedure pairs: 67 target-chain differences and 8 switch
case table permutations. No destination mismatch remained under these rules.
This does not change the comparer or certify arbitrary instruction differences.

- Chain traversal follows only unconditional Jmp or a repetition of the same
  short-circuit opcode (B2/B3). Traversal is cycle bounded. It does not skip
  conditional bodies, stack operations, calls, or exception handlers.
- Switch entries must preserve each string/numeric key's logical destination
  and the default destination. Duplicate keys are rejected rather than reordered.
  Six observed tables use string keys and two use numeric keys.

`dev-scripts/branch_route_dump.rs` accepts native DMB, translated DMB, and a TSV
file of native procedure ID / translated procedure ID / path. It prints the
executable instruction ordinals and decoded branch destinations to a text file.
`scripts/classify-branch-routes.py PARITY.ndjson BRANCH_BODIES.txt` checks only
the `branch_or_switch_operands_only` classification rows against that dump.
Use DMB files and IDs from the same parity report; allocation IDs are not portable
between emissions. The script deliberately leaves unrecognized forms unresolved.

This is a bounded route-layout classification, not a runtime execution test.
Try/break/continue frame cleanup is audited separately with native fixtures;
matching an eventual branch destination alone does not establish that contract.
