# Requirement retirement source handoff (2026-10-15)

## Scope and current proof

The old-code captures are committed in `d99315344b`: 29 fit snapshots (232 rows), 160 acceptance-type snapshots covering all 173 declarations, and one actual native item-override snapshot. The final acceptance/override repair run passed both selectors (`20261015T220049_fcc8559302.json` in the shared old-code capture worktree). Production conversions below have not yet been generated, compiled, tested or stamped; the coordinator owns the exclusive verification slot.

## Converted

- All 173 remaining acceptance table declarations: 149 mechanical declarations and 24 semantic declarations. Shared owner-key and taur-shape requirements replace repeated callbacks. Requirements return null or an ordered reason and preserve separate wearer/mover/slot context.
- Slot admission, item overrides, native equipment and vore-consent consumers now use native acceptance plans. Existing boolean effect-facing consent checks remain a view of a native refusal result, not a second requirement protocol.
- Removed the legacy predicate compiler, system-requirement compiler, their macros, source includes, adapters and zero-caller stance helpers. Numeric unit wrappers and legitimate request-result `REQ_*` enums remain.
- The requirement lint hard-bans the exact 81 retired requirement/holder/predicate macro names, including under engine paths. Its source matcher ignores comments, strings and larger identifiers. The existing boolean-callback ban remains enabled and rejects reintroduced definitions as well as calls.
- Native tests retain actual admission, field/list/access/stage requirements, hand context, numeric boundaries, reason ordering, subtype dispatch, override/adoption and consumer behavior. Grammar-only compiler tests are replaced by native validation and existing simulation-condition coverage.

## Source counts (not runtime proof)

| Source inventory | Before | After |
|---|---:|---:|
| Remaining acceptance table declarations | 173 | 0 |
| Mechanical / semantic declarations | 149 / 24 | 0 / 0 legacy declarations |
| Retired requirement, holder and predicate macro definitions | 81 | 0 |
| Exact retired macro names enforced by the hard ban | 0 | 81 |
| Live `req_bool(...)` calls | 0 | 0 |
| Live `needs = PROC_REF(...)` callback forms | 0 | 0 |

The post-edit lexical audit excludes comments and strings. Legitimate request outcome enums remain: `REQ_ANSWERED` 68, `REQ_CANCELLED` 204, `REQ_TIMED_OUT` 10, `REQ_TRANSPORT_FAILED` 14, `REQ_NO_RESULT` 6 and `REQ_FAILED` 1 (303 source mentions total). They are request results, not requirement declarations, and are not renamed or banned. The existing requirement baseline was already zero before this cohort; no ceiling or baseline was raised.

Three real formatting helpers used outside the retired compiler remain implemented: numeric property-unit formatting in the native property layer, and article/tool-quality names beside their actual tool consumer. These retain their existing bodies and refusal text; they are not compatibility aliases for the retired compiler.

## Intentional behavior corrections

`intended_changes.md` names the four specific causes: the malformed syndicate-gripper union (introduced in `0dfa07f646`); the duplicated numeric unit becoming the literal refusal `size`; and the two formerly impure saddlebag/Avida admission previews. Real equipment still applies the same sprite selection through synchronous equipment notices and setters. Fresh native captures refresh only the documented malformed-union and numeric-refusal rows. Generic pin updates remove the dead mecha key from master `f13b84652d` and add the devour key from master `2136172edc`; expanded menus and clicks are unchanged. No runtime or look failure is blessed.

## Verification evidence

Old-code captures are recorded before conversion. Native gate `f78dfcd117` passed production compilation (0 errors), DreamChecker (0 diagnostics), all ratchets and the analyzer tests. Its focused batch passed 57 tests, including both look pins, the requirement protocol pin, both constructor regressions, actual slot admission and telecube cleanup. Three failures were the stale master devour key inventory and two new fixture errors, repaired before the final failure-only gate: use a real behaviour-provider contract, and execute the timer deadline phase instead of advancing zero time.

The final lane-ready receipt and its focused-run JSON are the authoritative completion evidence, including mandatory `dq_requirement_protocol_pin` and `dq_conversion_pin`; this document is not a substitute for that stamp. The final selectors are recorded in ignored `data/codex-req-burndown/final-repair-selectors.txt`. No full suite is run, no runtime rows are re-blessed, and no baseline is raised. Existing gate-fixture state-leak warnings (`coalesce_runs`, `test_prompts`, NIFsoft caches and midnight counter) remain separate from the requirement conversion.
