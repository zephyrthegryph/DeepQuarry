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

`intended_changes.md` names the four specific causes: the malformed syndicate-gripper union (introduced in `0dfa07f646`); the duplicated numeric unit becoming the literal refusal `size`; and the two formerly impure saddlebag/Avida admission previews. Real equipment still applies the same sprite selection through synchronous equipment notices and setters. Existing old-code goldens remain unchanged pending actual native verification; only those documented cause classes may change.

## Verification plan

The exact selectors are in ignored `data/codex-req-burndown/native-focused-selectors.txt` (JSON counterpart records coverage), including mandatory `dq_requirement_protocol_pin` and `dq_conversion_pin`. The focused Rust filter is `requirement_bool` in package `dq-analyze`. No analyzer, generation, Rust, compilation, runtime test, baseline update or stamp is claimed for this production cohort yet.
