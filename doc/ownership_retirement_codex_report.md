# Ownership retirement handoff

Branch: `codex/ownership-retirement-1006`, started fresh from `origin/master` at `0add9783a0`. The prior timer/verb/I/O branch remains separate and was merged with master and pushed as `553421cbe8`.

## Changes

1. Reviewed the listed slots through ancestor and descendant ownership declarations. Migrated 26 explicit-clear calls in 16 production files. The rig's three unconditional destruction policies and hardlight-bow subtype bolt policy are declared DELETE. Conditional MMI, bait, radio key, canvas, AI card, golem spell and soulgem consumption keep their normal declared policy and override only the consuming call. Slots already declared DELETE use plain `rel_clear`. None of these candidates needs an inherited-start override; master's built bike already uses `no_starts`.
2. Migrated 67 take-all calls and 31 single-take calls. The LeMat's two dynamic calls were converted only after their policy pin passed. Removed the carried-affliction fallback `|| list()` because the native take-all always returns a list. Scalar callsites were checked for actual single-occupant shape, including dynamic hardware/slot accessors. Seven existing TGS integration take-all calls retain their arguments and semantics with the native spelling.
3. Eliminated all 13 `destroy_qdel_owned` baseline entries through ownership declarations, links or removal of redundant teardown disposal. The baseline has **407 -> 394 fingerprint rows**, with **destroy_qdel_owned 13 -> 0**. Parsed-map grid sets now honor their existing DELETE declaration instead of being detached and leaked; blank parser teardown tolerates absent bounds. Stock records keep handed-out products alive; parcel destruction retains relocation/unwelding effects; material-service batching retains watch-key collection and diagnostic cleanup.
4. Dynamic codec, serializer, fabricator, gas-watch and LeMat conversions: all four policy pins passed before conversion. Replaced both codec clears, serializer clear, fabricator clear, gas-watch list clear and both LeMat cylinder takes. The native baseline updater removed no further rows.
5. `code/engine/library/spaces.dm`'s two-argument `rel_take` is correct: it empties an explicitly single-occupant var slot. No engine source was changed. Existing cell-bay take/insert tests are selected for verification.

The native decl baseline updater was run after each completed step; steps 1 and 2 had no decl fingerprint changes, step 3 removed the 13 rows. No baseline was seeded or hand-edited. No new ALLOW annotation was added.

## Deliberate keeps

- `code/game/mecha/mecha.dm`, equipment salvage loop: keep the independent 30% roll for each salvageable item, including the different destruction path for failed rolls.
- `code/game/mecha/components/_component.dm`, `on_destroy`: keep `detach()` because it removes the component from the mech and preserves the existing teardown/order-dependent bookkeeping.
- Framework ownership implementation delegates and reserved engine callers remain on the low-level accessor. Compatibility tests still exercise those low-level APIs; this work does not remove the compatibility implementation.

## Additional fix

The existing P2 cell-bay test exposed a vanished datum in the legacy refresh queue. Added an immediate null-entry guard in `code/datums/capabilities/refresh.dm`, preserving the existing deleted-entry handling. A dedicated regression asserts the next live queued datum still receives its original change channel exactly once. No engine source was edited.

## Tests

Eighteen new focused regression types cover real bait consumption/removal, hardlight disposal and ordinary physical-arrow unloading, rig teardown, robot MMI ejection/dust, soulgem transfer, state decoding/reset policy, fabricator cleanup, actual watch deletion, cylinder identity/custody, carried-affliction release, card shuffling, parser deletion/empty teardown, stock-product retention, parcel spilling and automatic reference removal, actual particle-smasher dumping and refresh queue survival.

Selected existing tests additionally cover cell-bay take/insert (two), eager/lazy list shape, last-member removal and policy forwarding (three). The source policy pins inspect all current gas-watch list consumer declarations and all three LeMat cylinder declarations before the dynamic conversions.

Focused verification: the 23-case run passed 22 cases with a clean boot and no state/object leak lines. The remaining card assertion needed parentheses around DM membership; its isolated recheck passed. Together all 23 selected cases passed. The isolated recheck logged an informational `STATE LEAK?` for lazy initialization of the existing shared `GLOB.dview_mob` singleton; no mutable flag or object leak occurred, and no shared presentation lifecycle was altered to suppress it.

Results: `data/test-runs/20261006T223907_c86ff83934.json` (22 passed, one assertion corrected), `data/test-runs/20261006T224736_7184da7141.json` (corrected card test passed), and `data/test-runs/20261006T223215_c86ff83934.json` (existing P2 isolated passed). The four dynamic pins had also passed before any corresponding accessor conversion.

Final serial `tools/build/build.sh lint` passed with **0 DreamChecker diagnostics**; `tools/ci/check_ratchets.sh` passed. Final compile: **0 errors**, 28 existing warnings. Logs: `data/codex-ownership/final-lint-serial.log` and `data/codex-ownership/final-ratchets-serial.log`. Refetched origin before handoff: current `origin/master` remains `0add9783a0` and is an ancestor of this branch. No full suite, shard or E0 run was started.

Focused verification selection (exact types):

- `/datum/unit_test/dq_ownership_policy_bait_consumption`
- `/datum/unit_test/dq_ownership_policy_hardlight_bolt`
- `/datum/unit_test/dq_ownership_policy_rig_teardown`
- `/datum/unit_test/dq_ownership_policy_robot_dust`
- `/datum/unit_test/dq_ownership_policy_soulgem_transfer`
- `/datum/unit_test/ownership_retirement_codec_policy_pin`
- `/datum/unit_test/ownership_retirement_fabricator_policy_pin`
- `/datum/unit_test/ownership_retirement_gas_watch_policy_pin`
- `/datum/unit_test/ownership_retirement_lemat_policy_pin`
- `/datum/unit_test/ownership_retirement_carried_afflictions`
- `/datum/unit_test/ownership_retirement_card_shuffle`
- `/datum/unit_test/ownership_teardown_parser_deletes_grid_sets`
- `/datum/unit_test/ownership_teardown_stock_keeps_handed_out_product`
- `/datum/unit_test/ownership_teardown_delivery_spills_parcel`
- `/datum/unit_test/ownership_teardown_reference_drops_without_deleting_target`
- `/datum/unit_test/ownership_teardown_empty_parser`
- `/datum/unit_test/dq_p1/cell_bay_takes_and_inserts_behind_the_cover`
- `/datum/unit_test/dq_p2_lib/hatch_cell_bay_behind_the_cover`
- `/datum/unit_test/dq_lane_a_own/rel_take_all_always_returns_a_list`
- `/datum/unit_test/dq_lane_a_own/taking_the_last_member_keeps_an_eager_list`
- `/datum/unit_test/dq_lane_a_own/rel_clear_forwards_its_policy`
- `/datum/unit_test/dq_ownership_policy_smasher_dump`
- `/datum/unit_test/ownership_retirement_refresh_skips_deleted_queue_entry`
