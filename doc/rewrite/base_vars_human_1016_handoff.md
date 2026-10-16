# Human state homes - source handoff

The human-path inventory contains 44 baselined base fields (including living-base declarations in species files). This source-only cohort migrates 28; 16 reference fields remain for a separate reference/ownership cohort. Counts await analyzer verification; no baseline was edited and no build, generation, analyzer or runtime test was run here.

## Converted homes

* Five trait values: `human_abilities` owns spit projectile/name, regeneration delay and melee multiplier; `shred_settings` owns the living 45-second default with the human 10-second override. Original map/VV field names remain mapped. The regeneration delay is the same 300 deciseconds, expressed as `30 SECONDS`.
* Four character choices use the existing identity profile and tracked setters: custom species name, sensor preference, species-speech toggle and nutrition visibility. The AI-controlled type retains its sensor default of 1 through profile fields; humans retain 5. DNA retains its separate serialized custom-species field, with explicit import/export to the human profile.
* The actual body owns writing and marking-order state, revival eligibility, heartbeat cycle counter, chemical sight/environment caches and biological-time nutrition integration point. Existing writes now use native setters. These do not join the copied look profile: physical writing must not silently start copying with appearances. Existing marking-copy code still copies its counter explicitly after the actual organs.
* HUD refresh is a named cooldown with the same world-time minute deadline and non-extending early refresh. The health-doll cache belongs to the actual HUD datum.
* Sparse state retains pending regeneration, redgate restriction, human ability flags, the gender-drug pending flag, disability pressure/death progress and the picked tic list. The gender flag is deliberately not a timestamp. Tic RNG calls and persistence across revocation are unchanged.
* Flight-vore choice uses the existing `vore_options` record. Its original serialized trait key is routed by `apply_vore_option_trait`, including reset, rather than falling through to a deleted raw mob var.
* Deleted genuinely unused human `step_count` and write-only `low_sorting_priority`, including its nine subtype assignments. Same-named locals and robot counters remain untouched.

## Remaining 16 reference fields

`side_effects`, `wearing_rig`, `teleporters`, `genetic_side_effects`, `default_attack`, `synthetic`, `vr_holder`, `vr_link`, `ear_style`, `ear_secondary_style`, `tail_style`, `wing_style`, `shadekin`, `character_forms`, `trait_states`, `xenochimera`.

Eight borrowed/reference endpoints (default attack, synthetic model, the four shared sprite accessories and the VR pair) have straightforward sparse native-link homes; they are next-cohort source work, not claimed framework blockers. Preserve actual shared definition datum identity, not strings.

For the other eight, retain existing source until the ownership contract is explicit. Sparse `links(... b_on_other_deleted = OTHER_DELETE_ME)` deletes a child when its owner dies but does not implement the owned-field disposal on replacement, `rel_clear`, `rel_remove` and `own_remove`. Do not replace those calls with non-deleting `link_break` or add ad hoc qdel glue just to move the var. The rig additionally uses `ON_DESTROY_CONTAINED`: unconditional peer-death deletion would destroy a rig outside the human and change survival. A proper sparse ownership-policy form or reuse of an existing authoritative owner relationship is required.

## Verification pending

New include: `code/modules/unit_tests/dq_base_vars_human_home_tests.dm`, five leaves under `/datum/unit_test/dq_base_vars_human_homes`: `profile_preferences`, `body_writing`, `hud_refresh_clock`, `heartbeat_counter`, `flight_preference`. These exercise real preference application, the actual body, washing, Life heartbeat counting, the real HUD safety-refresh deadline and persisted trait-key apply/reset. Root owns the manifest and verification.

Existing focused regressions: `round2_gender_change_drug_request`, `dq_mob_every` (gibbing disability), vital-system/defibrillator and human profile/DNA tests, plus mandatory requirement/conversion pins. Existing fixture raw field accesses were changed to their native homes without blessing golden rows.

Source diff check passed. No runtime or stamp claimed.
