# Silicon module migration: source handoff

This records source changes and unresolved behavior contracts. Verification is
pending the coordinating lane's combined generation, lint and focused gate; this
worker has run no builds or tests. The old 35-type/window capture was reported
green before applying the changes.

## Converted behavior

- Concrete immutable viewer profiles live in `code/modules/mob/viewer_profile.dm`.
  AI-only, robot-only, all-silicon and human-or-AI fields stay distinct; profiles
  describe presentation and grant no control authority. A photocopier's misleading
  `isAI` field remains broad silicon. Fax/disposal camera fields remain AI-only.
- The two AI HUD camera questions are native actor-local menu operations, with
  the clicked screen retained as lifetime context. They use no wireless provider,
  keep their original prompt text, and cancel when their source screen disappears.
  The existing camera fixture now observes the pending operation and real eye
  movement rather than requiring the removed callback replay mechanism.
- Communications state selection, modular-computer boot messages, RIG power,
  robot-control credentials, disposal insertion and hologram feed distance use
  typed transactions or actual values, rather than disguised actor-kind booleans.
  Borg ordinary disposal hand insertion still stops after bag/ashtray handling;
  dragging remains allowed. A robot's active override card is not its built-in ID.
- Recharge-station admission is a scripted operation (`ai()` explicitly supports
  script calls) with `ORIGIN_SYSTEM`, the passenger as actor, ordered requirements
  and a body-owned admission policy. It does not grant wireless authority. Occupancy
  precedes body checks; robot incapacity and missing-cell checks precede platform
  size refusal. Unconscious rig-wearing humans retain forced/bump admission.
  Fingerprinting still precedes the slot transfer, and work starts only on success.
- The unused silicon-disallow use-check bit and failure code are removed. The only
  production `use_check` caller passes literal zero; the remaining flag bit values
  and return codes are unchanged.

## Remaining exact contracts

### Six casino stages

`code/modules/casino/casino.dm` remains unchanged at `wheel_use_stage`,
`wheel_management_stage`, `wheel_interval_stage`, `spasm_use`, `spasm_id` and
`setprice/recheck`. These complete flows perform observable effects between
questions: UI refresh while the next question is open, repeated access messages,
stale-collar relation/key cleanup before confirmation, and custom invalid-price
or interval feedback. The nested interval path also has different admission from
the independent verb. Pure `asks(when/valid)` cannot perform those effects.

A declared intermediate effect/commit step with cancellation and refresh semantics
is needed. Moving cleanup to a final handler, writing from a computed prompt field,
or wrapping the old predicate would change the flow instead of converting it.

### Hoist detach propagation

`code/modules/multiz/hoist.dm:drop_input` has an expressible source/target context:
`at_target()`, drag gesture, zero affordance and any reach. The blocker is that old
input always falls through, including after successful detach and after ordered
incapacity/tool refusal messages. `passes()` falls through only committed ops;
a native requirement refusal consumes input, while a false selector loses feedback.
A declared refusal-fallthrough contract or approved propagation change is needed.

### Legacy machine refresh

`machine_shim.dm:updateUsrDialog` remains unchanged. The old `actor_use` route
skips engine resolution when `GLOB.op_click_resolved` already marks the current
input. Blindly submitting a new click during the operation effect can queue the
same action repeatedly. The remaining callers need native linked-presentation
refresh/nested-input suppression, or complete retirement as UI output updates.
There are 23 call sites plus the definition in the current source search.

## New focused fixtures (not yet run)

`dq_silicon_residual_tests.dm` adds local HUD cancellation/source deletion and
actor isolation, viewer role distinctions including pAI, communications channel
selection, borg disposal hand/drag/bag ordering, recharge body admission and ordered
platform refusals, and actual RIG cell spending. The existing screen-camera fixture
still checks successful selection and actual eye movement. Other existing C2 and
coordinator-owned device fixtures remain separate; this document claims no test
result or stamp.
