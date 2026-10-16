# Behaviour state homes — source handoff

The `code/datums/behaviours` cohort removes 24 of 29 baselined base-type fields from ten files. This is a source count, pending analyzer shrink and verification. No baselines, generated files, builds or tests were run for this cohort.

* Conflict identity, sale profile and four footstep sound settings are native inherited type traits. Their original field names remain in `var_names` for map/VV compatibility; runtime footstep and sale overrides use copy-on-write `set_trait`.
* Omen modifiers/budget, slosh counters/cache, radiation exposure timestamps, the light-blocking flag, tether path and swarm offsets/flag are sparse per-instance scalar state. Postfix slosh increments and state persistence across revocation are preserved.
* Swarm membership uses a native sparse reciprocal many-to-many link. Burning retains its original five fields and cooling-watch ownership because the custom fire appearance has no equivalent activation-scoped native output yet.

## Source split

The behaviour commit owns the following files, plus this handoff (check shared files before staging, since other lanes may have added disjoint hunks):

* `code/__defines/engine/link_keys.dm`
* `code/datums/behaviours/burning.dm`
* `code/datums/behaviours/conflict_checking.dm`
* `code/datums/behaviours/footstep.dm`
* `code/datums/behaviours/light_blocking.dm`
* `code/datums/behaviours/omen.dm`
* `code/datums/behaviours/radiation_countdown.dm`
* `code/datums/behaviours/sellable.dm`
* `code/datums/behaviours/slosh.dm`
* `code/datums/behaviours/swarming.dm`
* `code/datums/behaviours/tethered_item.dm`
* `code/game/atoms_movable.dm`
* `code/game/machinery/pandemic.dm`
* `code/library/providers/hands.dm`
* `code/modules/combat_ai/integration/mob_living.dm`
* `code/modules/emotes/definitions/audible_snap.dm`
* `code/modules/mining/kinetic_crusher.dm`
* `code/modules/mob/living/carbon/carbon.dm`
* `code/modules/mob/living/silicon/silicon.dm`
* `code/modules/mob/living/simple_mob/simple_mob.dm`
* `code/modules/paperwork/paper.dm`
* `code/modules/projectiles/guns/energy/kinetic_accelerator.dm`
* `code/modules/unit_tests/dq_h3_heat_tests.dm`
* `code/modules/unit_tests/dq_retired_behaviour_pins.dm`
* `code/modules/unit_tests/interim_mining_conflict_data.dm`
* `code/modules/unit_tests/dq_base_vars_behaviour_tests.dm`
* `code/modules/xenoarcheaology/effect_master.dm`

`code/modules/lighting/lighting_atom.dm` is shared with the lighting cohort. The behaviour hunk ONLY replaces `ref_many(nameof(swarm_members))` in the existing `/atom/movable` block with `links(LINK_END(/atom/movable, LK_SWARM_MEMBERS), LINK_END(/atom/movable, LK_SWARM_MEMBERS), sparse = TRUE, a_many = TRUE, b_many = TRUE)`. Preserve all lighting-agent changes; stage only that hunk with this cohort, or have root combine the shared-file source after both cohorts are complete. No duplicate CAPABILITIES blocks were introduced.

## Focused verification pending

New file: `code/modules/unit_tests/dq_base_vars_behaviour_tests.dm` (root wires its include). Seven leaves under `/datum/unit_test/dq_base_vars_behaviours/`: `light_source`, `omen_merge`, `footstep_overrides`, `slosh_counter`, `sale_profile`, `burning_watch_lifetime`, `radiation_countdown`.

Existing focused regressions to run: `dq_retired_omen_capability`, `dq_retired_footstep_counts_steps`, `dq_retired_swarming_pairs_on_a_turf`, `dq_retired_tether_swap_and_return`, `interim_mining_conflict_data`, `dq_h3_burning_ends`. The new tests assert actual opacity registration and movement, omen merge/consumption, isolated sound overrides, postfix counter persistence, first-profile-wins, actual cooling-watch deletion and timer-driven exposure expiry. Existing tests now read the real native state homes.

Source-only `git diff --check` passed. No affected map field overrides or raw production field consumers remained in the audited tree. Runtime and lint results are not yet available; no stamp claimed.

The attempted fire-state context conversion is withdrawn; there is no new runtime record or data-only-record exception.

## Unlanded burning conversion withdrawn

Five original master fields remain: burn_overlay, burn_particle_type, burn_fuel, burn_cool_watch and burn_ended_by. Granted capability draw providers are not consumed by the current presentation path, and native granted look layers cannot represent the arbitrary retained mutable appearance accepted by start_burning(). The conversion and its premature five-row baseline removal were backed out. This introduces no master baseline rows: the final baseline is a strict subset of origin/master. The lifetime regression now tests the retained real cooling-watch ownership.
