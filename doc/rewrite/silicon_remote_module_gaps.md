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

### Two casino flows with repeated pre-question messages

Source review against master `86fe6ef554` confirms two casino flows still need
an effect at question boundaries: `wheel_management_stage` and `spasm_id` emit
`Proper access, allowed staff controls.` before the first question and again on
resumption. Their cancellation paths already emitted that message. Moving it to
the final effect would change visible chat/history. The stale-collar cleanup in
`spasm_id` is terminal, not a separate pre-next-question mutation; the repeated
message is the actual blocker.

Current `asks()` has no declared before-question/after-answer feedback phase.
`then()` before a later question is rejected by `op_plan_check_order`; `starts()`
and `begins()` run only when a real timed wait starts. Adding a fake timed wait or
writing from computed fields would change behavior rather than express this
contract. A native question-boundary feedback form or an approved change to the
repeated chat is needed; no general UI-refresh gap remains.

The other three flows now use existing forms: the former `wheel_use_stage` chains
its choice and conditional interval question; the former `wheel_interval_stage`
is a numeric question followed by a range requirement and assignment; `setprice`
delegates its leaf transaction to a native script-bound operation. Neither machine declares an interface or
`ui_data()`, so its existing `SStgui.update_uis()` calls have no open declared
window to update. They are not evidence for an intermediate-effect framework gap.
The standalone interval menu's initial adjacency/capability requirements must not
be strengthened into resumed range checks; the nested interval branch never had
that admission. The numeric input must preserve its UI bounds while allowing the
real final range check to refuse invalid submitted answers without writing state.
The coordinator ran all three old-production AI/borg flow tests successfully on
production `4ab2e15fe1` (`20261016T005159_5b6663b70b.json`, three passes, zero
failures), then authorized application. Their native adaptations exercise the
actual menu/script operation and asks paths. Native verification remains pending;
no new gate is claimed here. The two repeated-message flows and hoist remain. The 23-call refresh cohort and
SPASM ordinary-use flow bring the source inventory to 100 of the original 103 rows
converted (three remain); their native gate is pending.

### Converted SPASM ordinary-use flow

`spasm_use` was re-audited rather than assumed blocked: its stale-collar cleanup
belongs only to terminal branches, and registration checks between questions are
pure. The existing `spasm_use` operation now chains conditional `asks()` steps and
commits the same selection, information, registration and payout effects after
its last answer. Sale admission stays initial-only, and no resumed adjacency
requirement is added. Native ability/status invalidation remains active while the
questions are open. A clientless registration attempt closes silently without
creating a collar, identity entry or payout; the actual client and duplicate
membership are requirements, not effect-head guards. The newly reactive identity
list's existing append and six removals use generated list setters.

The exact type had pre-conversion human/AI/borg menu pins in the completed
`dc46845b50` capture, including its disabled-sale refusal. The new focused native
branch fixture drives actual AI/borg inputs, real collar selection, cancellation,
information, deleted selection and clientless registration. It is new native
coverage, not a claimed old-flow test run. Positive registration with a live client
is not exercised by this headless fixture, and no fake client identity is supplied.

### Hoist detach propagation

`code/modules/multiz/hoist.dm:drop_input` has an expressible source/target context:
`at_target()`, drag gesture, zero affordance and any reach. The blocker is that old
input always falls through, including after successful detach and after ordered
incapacity/tool refusal messages. `passes()` falls through only committed ops;
a native requirement refusal consumes input, while a false selector loses feedback.
A declared refusal-fallthrough contract or approved propagation change is needed.

### Retired refresh caller cohort

The former `machine_shim.dm:updateUsrDialog` row is removed. A current-source audit
found 17 of its 23 calls already belonged to eight existing declared TGUI hosts;
this was not a missing-window framework barrier. They now call existing
`refresh_ui(src)`, which queues coalesced data output through
`presentation_refresh_windows` and `ui_push_mark`, without replaying a hand or
remote operation. Duplicate explicit updates in the same UI call chain are removed.

Two area-editor calls were provable no-ops after setting `in_use = FALSE` and are
removed. The base beacon's four calls could not render a window after its entry
became `asks()`; they only reached the remaining touch gate and are removed.
No recruitment, shipment, inventory, game action or permission logic changes.
The other 78 references to the using-machine lifetime helpers still need their
separate migration: their datum, helper procs, source file and build include remain.

The completed `dc46845b50` gate compared seven exact host goldens with real AI and
borg rows unchanged (only mismatches write diagnostic captures). Dartgun had no
exact per-type pin, so the coordinator separately captured its old behavior:
`20261016T023039_a49b5d8504`, one pass, zero failures. The two new native UI tests
exercise real dartgun insertion/mixing and the magnetic controller speed button,
checking queued data, real window output and no repeated action. Their native
validation is pending; no new gate or pin re-bless is claimed.

## New focused fixtures (not yet run)

`dq_silicon_residual_tests.dm` adds local HUD cancellation/source deletion and
actor isolation, viewer role distinctions including pAI, communications channel
selection, borg disposal hand/drag/bag ordering, recharge body admission and ordered
platform refusals, and actual RIG cell spending. The existing screen-camera fixture
still checks successful selection and actual eye movement. Other existing C2 and
coordinator-owned device fixtures remain separate; this document claims no test
result or stamp.
