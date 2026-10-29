# Initial-setting-prefix proof (draft, not verified)

Apply order: current typed-variable WIP, then
`return-constructor-policy.draft.patch`, then `initial-setting-prefix.draft.patch`.
Generator only transforms strings and emits an ignored patch; no source was
changed and no Rust build/test was run by this agent.

The prefix is borrowed from the SAME retained primary BodySyntax query node.
The callback cannot retain syntax borrowed from the temporary parse guard.
Exact authored callable identity is selected from the archive's existing roster;
the consumer also requires pointer-identical tree/archive provenance. There is no
new parser, model, QueryDb, inferred-return query or semantic recursion. Recursive
calls request a completed primary syntax node, never their own semantic policy
result. Existing entrypoints without a retained graph remain Unsupported when
settings need proof.

Only contiguous top-level initial `set` statements count. The first non-set
stops the prefix, including an `if`; nested and later sets do not affect return
or call-directive facts. Literal absolute return paths and null are supported;
dynamic TypeExpr directives and all other SpacemanDMM directive policies remain
Unsupported. Ordinary runtime settings do not alter argument visitation or
return type; their diagnostics remain the existing settings family's concern.

Independent pinned checker 0290db5c752fa292f9824521515b603a2afd11dc
(GPL-3.0), `gather_settings` lib.rs:756, establishes header first and then
contiguous settings, last return override wins. Independent executable capture
`return-prefix-reference.stderr.txt` contains ALL three observations:

- (7,5) error: `set statement not at the top of the proc`
- (10,12) error: `undefined field: "absent_early" on /datum/target`
- (11,11) warning: `field access requires static type: "absent_late"`, note
  `(5,11) add a return type annotation to /proc/late`.

The third warning/fix-hint family is NOT implemented. Do not filter it and claim
full fixture parity. This cohort proves prefix return facts and the existing
late-set diagnostic independently; whole-body field warning output remains
explicit Unsupported. The draft does not promise full checker parity.

Root verification: targeted dm-tree/dmbc tests matching `initial_settings`,
`initial_return_settings`, `source_edit_retracts_prefix`; then existing
checker-return facts, constructor/header tests and source named-policy tests.
No Cargo was run here. The new tests cover primary eviction, same-owner proof,
foreign archive rejection, unknown identity, early/late/nested sets, last-wins,
null clearing, and edits retaining the old immutable archive.
