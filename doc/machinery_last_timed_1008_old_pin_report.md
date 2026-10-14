# Last machinery timed conversions: old-code baseline

Recorded on codex/machinery-audit-1008 at e03f6c58d6, before changing medical_kiosk.dm, cryopod.dm, suit_storage/suit_cycler.dm or computer/ai_core.dm. Source hashes are in machinery_last_timed_1008_old_pin_provenance.json. The explicit focus list is machinery_last_timed_1008_old_focus.txt.

The final old-code run passed all 34 tests, with a clean boot and no state/object leaks. DreamMaker: 0 errors, 50 existing warnings. Result: data/test-runs/20261008T170203_e03f6c58d6.json. No full suite, shards or Rust build ran. DreamChecker/lint/ratchets have not been rerun for this test-only baseline commit.

The four scoped conversion snapshots matched without blessing. Behavior pins cover kiosk service completion, cancellation, timeout, opened panel, movement and competing patient; cryopod consent, refusal, cancellation, moving loader and deleted passenger; the real powered cycler shock; and completion/drop/movement for five AIcore tool paths. Four previous typed-prompt repair checks and two existing cycler checks also passed.

## Entry-point boundaries

AIcore clicks currently do not reach its handwritten wrench_act/welder_act hooks: the native item catch-all intercepts them. The initial real-click run demonstrated this in all fifteen checks. Old-code behavior pins therefore invoke the actual tool_act dispatcher (not completion callbacks), preserving real use_tool waits and all state/custody/cost assertions. After native conversion they must switch to real clicks, documenting repaired input dispatch as an intended change.

The headless cryopod tests bypass only its network-client admission by opening the existing real cryo_consent request with passenger answerer and separate loader. They retain its production callback and timed task. The native conversion must replace that test admission with the native op, using a test-only consent-needed predicate for the clientless passenger.

## Dependency pending

After repeated fetches origin/master remains 6cf9e920d7. Its asks signature has no answerer and its starts handlers ignore return values. The existing implementation is local rewrite/notices-asks at ad65c84b32; rewrite/integ-12 does not contain that commit. Native drafts for the three machinery cases and five AIcore paths are prepared but unapplied. Production and timed_forms_converted remain unchanged pending publication or an explicit source-ref instruction.
