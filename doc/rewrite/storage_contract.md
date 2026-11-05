# Storage contract: lazy owned state

The design is in `E:/projects/dq-design-review/` (migration plan S3, `lazy_and_variables.md`). This file is the repo-side record of the form and of the grouping of the old `sparse()` slots into state datums.

## The form

Rarely used state is the vars of a small datum the holder owns, made on the first write:

```dm
/datum/omen_state
	var/damage = 1

CAPABILITIES(/mob/living)
	owns_one(nameof(omen), /datum/omen_state, lazy = TRUE)
```

- Read: `STATE_GET(A, omen, damage)`, the field, or the state type's own default (`/datum/omen_state::damage`) while no state exists. It allocates nothing. `A` is a var or `src` (it is evaluated twice).
- Write: `omen_of(A).set_damage(2)`. `omen_of()` is a generated global proc that makes the datum on its first call. The state's vars are tracked; a write publishes the var on the state and the holder's `omen` key, so draws, stats and `on_change()` that read it follow.
- End: `omen_clear(A)` deletes the datum when a feature clearly ends. Otherwise it lives until the holder dies; a write back to the default frees nothing.
- The state type is `/datum/<var>_state` (the generator refuses another name). No proc is added to `/mob`, `/atom` or `/datum`.

## Grouping of the old sparse slots

One state per declaring feature. A slot with no obvious feature goes to its holder's `*_misc` state. Waves: 1 = mob holders (converted first), 0 = waits (a list or weak slot, which needs hand work, or an atom/object holder, which waits on the base-type memory decision: one more var on `/atom` costs about 8 bytes on every instance). Defaults are what every `sparse_get_or(..., default)` call site gave.

Generated from `tools/analyze/codemods/sparse_state/groups.tsv` (`groups.py`); edit `groups.py`, not this table by hand.

### `/atom`

| Feature (owned var) | Slot = field | Kind | Default | Wave |
|---|---|---|---|---|
| `(no feature yet)` | `armor_override` | weak | `` | 0 |
| `(no feature yet)` | `atom_colours` | list | `` | 0 |
| `(no feature yet)` | `atom_integrity` | num | `max_integrity` | 0 |
| `(no feature yet)` | `catalogue_delay` | num | `` | 0 |
| `(no feature yet)` | `chat_color` | color | `` | 0 |
| `(no feature yet)` | `chat_color_darkened` | color | `` | 0 |
| `(no feature yet)` | `chat_color_name` | text | `` | 0 |
| `(no feature yet)` | `examine_icon_snapshot` |  | `` | 0 |
| `(no feature yet)` | `light_flags` | num | `NONE` | 0 |
| `(no feature yet)` | `map_json_data` |  | `` | 0 |
| `(no feature yet)` | `observer_listeners` | list | `` | 0 |
| `(no feature yet)` | `surface_germs` | num | `0` | 0 |
| `(no feature yet)` | `tf_offset_x` | num | `` | 0 |
| `(no feature yet)` | `tf_offset_y` | num | `` | 0 |
| `(no feature yet)` | `tf_rotation` | num | `` | 0 |
| `(no feature yet)` | `tf_scale_x` | num | `` | 0 |
| `(no feature yet)` | `tf_scale_y` | num | `` | 0 |
| `(no feature yet)` | `z_update_images` | list | `` | 0 |

### `/atom/movable`

| Feature (owned var) | Slot = field | Kind | Default | Wave |
|---|---|---|---|---|
| `(no feature yet)` | `affecting_dynamic_lumi` | num | `0` | 0 |
| `(no feature yet)` | `autotransferable` | bool | `TRUE` | 0 |
| `(no feature yet)` | `belly_cycles` | num | `0` | 0 |
| `(no feature yet)` | `blocks_light` | bool | `FALSE` | 0 |
| `(no feature yet)` | `cloak_selfimage` | /image | `` | 0 |
| `(no feature yet)` | `cloaked` | bool | `FALSE` | 0 |
| `(no feature yet)` | `dynamic_lights` | list | `` | 0 |
| `(no feature yet)` | `hovering` | bool | `` | 0 |
| `(no feature yet)` | `icon_rotation` | num | `DEFAULT_ICON_ROTATION` | 0 |
| `(no feature yet)` | `is_swarming` | bool | `FALSE` | 0 |
| `(no feature yet)` | `last_high_pressure_movement_air_cycle` | num | `0` | 0 |
| `(no feature yet)` | `last_move` | num | `0` | 0 |
| `(no feature yet)` | `listening_recursive` | num | `NON_LISTENING_ATOM` | 0 |
| `(no feature yet)` | `move_resist` | num | `MOVE_RESIST_DEFAULT` | 0 |
| `(no feature yet)` | `moved_recently` | num | `0` | 0 |
| `(no feature yet)` | `parachute` | bool | `FALSE` | 0 |
| `(no feature yet)` | `parachuting` | bool | `` | 0 |
| `(no feature yet)` | `recursive_listeners` | list | `` | 0 |
| `(no feature yet)` | `softfall` | bool | `` | 0 |
| `(no feature yet)` | `swarm_offset_x` | num | `0` | 0 |
| `(no feature yet)` | `swarm_offset_y` | num | `0` | 0 |
| `(no feature yet)` | `throw_source` | weak | `` | 0 |

### `/mob`

| Feature (owned var) | Slot = field | Kind | Default | Wave |
|---|---|---|---|---|
| `attacker` | `lastattacker_key` | text | `""` | 1 |
| `attacker` | `lastattacker_name` | text | `""` | 1 |
| `connection` | `autowhisper` | bool | `FALSE` | 1 |
| `connection` | `autowhisper_mode` | text | `` | 1 |
| `connection` | `away_from_keyboard` | bool | `FALSE` | 1 |
| `connection` | `computer_id` | text | `` | 1 |
| `connection` | `disconnect_time` | num | `` | 1 |
| `connection` | `lastKnownIP` | text | `` | 1 |
| `connection` | `manual_afk` | bool | `FALSE` | 1 |
| `mob_misc` | `LAssailant` | weak | `` | 0 |
| `mob_misc` | `accumulated_rads` | num | `0` | 1 |
| `mob_misc` | `active_genes` | list | `` | 0 |
| `mob_misc` | `ajourn` | num | `0` | 1 |
| `mob_misc` | `bhunger` | num | `0` | 1 |
| `mob_misc` | `bloody_hands` | num | `0` | 1 |
| `mob_misc` | `buckle_pixel_y` | num | `0` | 1 |
| `mob_misc` | `damageoverlaytemp` | num | `0` | 1 |
| `mob_misc` | `digitalcamo` | num | `0` | 1 |
| `mob_misc` | `disabilities` | num | `0` | 1 |
| `mob_misc` | `emote_sound_mode` |  | `EMOTE_SOUND_VOICE_FREQ` | 1 |
| `mob_misc` | `facing_dir` | num | `` | 1 |
| `mob_misc` | `floatiness` | num | `0` | 1 |
| `mob_misc` | `forbid_seeing_deadchat` | bool | `FALSE` | 1 |
| `mob_misc` | `get_rig_stats` | num | `0` | 1 |
| `mob_misc` | `global_hud_claims` | list | `` | 0 |
| `mob_misc` | `hive_lang_range` | num | `0` | 1 |
| `mob_misc` | `in_throw_mode` | num | `0` | 1 |
| `mob_misc` | `inertia_dir` | num | `0` | 1 |
| `mob_misc` | `is_floating` | num | `0` | 1 |
| `mob_misc` | `is_slipping` | bool | `FALSE` | 1 |
| `mob_misc` | `last_emote_summary` | text | `` | 1 |
| `mob_misc` | `lastareachange` | num | `0` | 1 |
| `mob_misc` | `lastattacker` | weak | `` | 0 |
| `mob_misc` | `logging` | list | `` | 0 |
| `mob_misc` | `m_int` | text | `` | 1 |
| `mob_misc` | `misc_tabs` | list | `` | 0 |
| `mob_misc` | `muffled` | bool | `FALSE` | 1 |
| `mob_misc` | `name_archive` | text | `` | 1 |
| `mob_misc` | `narglow` | /image | `` | 1 |
| `mob_misc` | `narsimage` | /image | `` | 1 |
| `mob_misc` | `other_mobs` | num | `` | 1 |
| `mob_misc` | `progressbars` | list | `` | 0 |
| `mob_misc` | `registered_z` | num | `` | 1 |
| `mob_misc` | `riftimage` | /image | `` | 1 |
| `mob_misc` | `seer` | num | `0` | 1 |
| `mob_misc` | `skincmds` | list | `` | 0 |
| `mob_misc` | `skip_buckled_move_redirect` | bool | `FALSE` | 1 |
| `mob_misc` | `suiciding` | num | `0` | 1 |
| `mob_misc` | `teleop` | weak | `` | 0 |
| `mob_misc` | `updating_fullness` | bool | `FALSE` | 1 |
| `mob_misc` | `vantag_hud` | num | `0` | 1 |
| `mob_misc` | `ventcraw_item_admin_allow` | list | `` | 0 |
| `mob_misc` | `voice_freq` | num | `42500` | 1 |
| `mob_misc` | `voice_sounds_list` | list | `` | 0 |
| `motion_track` | `is_motion_tracking` | bool | `FALSE` | 1 |
| `motion_track` | `wants_to_see_motion_echos` | bool | `TRUE` | 1 |
| `resting_flags` | `dizzy_was_resting` | bool | `` | 1 |
| `resting_flags` | `jittery_was_resting` | bool | `` | 1 |
| `resting_flags` | `lying_prev` | num | `0` | 1 |
| `spont_belly` | `spont_belly_front` | text | `` | 1 |
| `spont_belly` | `spont_belly_left` | text | `` | 1 |
| `spont_belly` | `spont_belly_rear` | text | `` | 1 |
| `spont_belly` | `spont_belly_right` | text | `` | 1 |
| `vr_state` | `died_in_vr` | bool | `FALSE` | 1 |

### `/mob/living`

| Feature (owned var) | Slot = field | Kind | Default | Wave |
|---|---|---|---|---|
| `autofire` | `autofire_delay` | num | `0` | 1 |
| `autofire` | `autofire_params` | text | `` | 1 |
| `autofire` | `autofire_target` | weak | `` | 0 |
| `body_effect` | `body_effect_data` | list | `` | 0 |
| `body_effect` | `body_effect_serial` | num | `0` | 1 |
| `body_effect` | `body_effect_timers` | list | `` | 0 |
| `bodyweight` | `weight` | num | `DEFAULT_MOB_WEIGHT` | 1 |
| `bodyweight` | `weight_gain` | num | `1` | 1 |
| `bodyweight` | `weight_loss` | num | `0.5` | 1 |
| `breath_hazard` | `air_hazard_at` | num | `-1` | 1 |
| `breath_hazard` | `air_hazard_breath_at` | num | `-1` | 1 |
| `breath_hazard` | `failed_last_breath` | num | `0` | 1 |
| `capture` | `capture_caught` | bool | `FALSE` | 1 |
| `capture` | `capture_crystal` | bool | `TRUE` | 1 |
| `custom_temp` | `custom_cold` | list | `` | 0 |
| `custom_temp` | `custom_heat` | list | `` | 0 |
| `footfall` | `footstep_steps` | num | `0` | 1 |
| `footfall` | `footstep_vary` | bool | `FALSE` | 1 |
| `gut_disability` | `disability_death_time` | num | `FALSE` | 1 |
| `gut_disability` | `disability_gut_pressure` | num | `0` | 1 |
| `living_misc` | `adminbus_eat_minerals` | bool | `FALSE` | 1 |
| `living_misc` | `buildmode_selected_image` | /image | `` | 1 |
| `living_misc` | `churn_count` | num | `0` | 1 |
| `living_misc` | `composition_reagent_quantity` | num | `` | 1 |
| `living_misc` | `custom_link` | text | `` | 1 |
| `living_misc` | `faction_affiliations` | list | `` | 0 |
| `living_misc` | `holder_default` | text | `` | 1 |
| `living_misc` | `injury_trace` | list | `` | 0 |
| `living_misc` | `life_z` | num | `0` | 1 |
| `living_misc` | `mute_entry` | bool | `FALSE` | 1 |
| `living_misc` | `photosynthesis_boost` | num | `0` | 1 |
| `living_misc` | `pickup_active` | bool | `TRUE` | 1 |
| `living_misc` | `pipes_shown` | list | `` | 0 |
| `living_misc` | `revival_in_progress` | bool | `FALSE` | 1 |
| `living_misc` | `skin_reagent` | text | `` | 1 |
| `living_misc` | `summoned` | bool | `` | 1 |
| `living_misc` | `temp_languages` | list | `` | 0 |
| `living_misc` | `tf_form_holds_key` | bool | `FALSE` | 1 |
| `living_misc` | `tod` | text | `` | 1 |
| `living_misc` | `touch_reaction_flags` | num | `` | 1 |
| `living_misc` | `trash_catching` | bool | `FALSE` | 1 |
| `living_misc` | `updating_cult_vision` | num | `0` | 1 |
| `melee_swing` | `is_swinging` | bool | `FALSE` | 1 |
| `melee_swing` | `melee_swing_resolving` | bool | `FALSE` | 1 |
| `melee_swing` | `melee_swing_serial` | num | `0` | 1 |
| `omen` | `omen_damage` | num | `1` | 1 |
| `omen` | `omen_evil` | bool | `TRUE` | 1 |
| `omen` | `omen_incidents` | num | `INFINITY` | 1 |
| `omen` | `omen_luck` | num | `1` | 1 |
| `omen` | `omen_safe_disposals` | bool | `FALSE` | 1 |
| `omen` | `omen_vorish` | bool | `TRUE` | 1 |
| `passtable` | `passtable_crawl_checked` | bool | `FALSE` | 1 |
| `passtable` | `passtable_reset` | bool | `` | 1 |
| `rad_countdown` | `rad_countdown_minimum` | num | `0` | 1 |
| `rad_countdown` | `rad_countdown_started` | num | `0` | 1 |
| `slosh` | `slosh_chance` | num | `0` | 1 |
| `slosh` | `slosh_steps` | num | `0` | 1 |
| `slosh` | `slosh_volume` | num | `0` | 1 |
| `tm_instability` | `last_instability` | num | `0` | 1 |
| `tm_instability` | `last_instability_event` | num | `0` | 1 |
| `trait_injection` | `trait_injection_amount` | num | `5` | 1 |
| `trait_injection` | `trait_injection_reagents` | list | `` | 0 |
| `trait_injection` | `trait_injection_selected` |  | `` | 1 |
| `trait_injection` | `trait_injection_verb` | text | `"bite"` | 1 |
| `vent_crawl` | `is_ventcrawling` | bool | `FALSE` | 1 |
| `vent_crawl` | `ventcrawl_layer` | num | `3` | 1 |
| `vore_fx` | `absorbing_prey` | num | `0` | 1 |
| `vore_fx` | `appendage_alt_setting` | bool | `FALSE` | 1 |
| `vore_fx` | `digestion_in_progress` | bool | `FALSE` | 1 |
| `vore_fx` | `drain_finalized` | num | `0` | 1 |
| `vore_fx` | `eggs` | num | `0` | 1 |
| `vore_fx` | `flight_vore` | bool | `FALSE` | 1 |
| `vore_fx` | `liquidbelly_visuals` | bool | `TRUE` | 1 |
| `vore_fx` | `prey_controlled` | bool | `FALSE` | 1 |
| `vore_fx` | `stuffing_feeder` | bool | `FALSE` | 1 |
| `vore_fx` | `vomiting` | bool | `` | 1 |
| `vore_fx` | `vore_egg_type` | text | `"egg"` | 1 |

### `/mob/living/carbon`

| Feature (owned var) | Slot = field | Kind | Default | Wave |
|---|---|---|---|---|
| `carbon_misc` | `addiction_counters` | list | `` | 0 |
| `carbon_misc` | `breath_cycle` | num | `0` | 1 |
| `carbon_misc` | `germs_rolled_at` | num | `` | 1 |
| `carbon_misc` | `last_taste_text` | text | `""` | 1 |
| `carbon_misc` | `synth_reag_processing` | bool | `TRUE` | 1 |
| `dream_seq` | `current_dream` | /datum/dream | `` | 1 |
| `dream_seq` | `dream_fragments` | list | `` | 0 |
| `dream_seq` | `dream_wait` | num | `0` | 1 |
| `posing` | `pose` | text | `` | 1 |
| `posing` | `pose_move` | bool | `FALSE` | 1 |

### `/mob/living/carbon/human`

| Feature (owned var) | Slot = field | Kind | Default | Wave |
|---|---|---|---|---|
| `contract_trial` | `clinical_exposure_history` | list | `` | 0 |
| `contract_trial` | `contract_medical_indications` | list | `` | 0 |
| `dq_vitals` | `dq_last_bodytemperature` | num | `` | 1 |
| `dq_vitals` | `dq_last_neural_load` | num | `` | 1 |
| `dq_vitals` | `dq_last_radiation` | num | `` | 1 |
| `human_misc` | `body_writing` | list | `` | 0 |
| `human_misc` | `can_defib` | num | `1` | 1 |
| `human_misc` | `changeling_locked` | bool | `` | 1 |
| `human_misc` | `chemical_darksight` | num | `0` | 1 |
| `human_misc` | `damage_multiplier` | num | `1` | 1 |
| `human_misc` | `disability_motor_tics` | list | `` | 0 |
| `human_misc` | `environment_steady` | bool | `FALSE` | 1 |
| `human_misc` | `gender_change_cooldown` | num | `0` | 1 |
| `human_misc` | `health_doll_key` | text | `` | 1 |
| `human_misc` | `heartbeat` | num | `0` | 1 |
| `human_misc` | `markings_len` | num | `0` | 1 |
| `human_misc` | `nutrition_drained_at` | num | `0` | 1 |
| `human_misc` | `nutrition_hidden` | bool | `FALSE` | 1 |
| `human_misc` | `original_player` | text | `` | 1 |
| `human_misc` | `pale` | num | `0` | 1 |
| `human_misc` | `resleeve_lock` |  | `` | 1 |
| `human_misc` | `special_voice` | text | `""` | 1 |
| `human_misc` | `speech_sound_enabled` | bool | `TRUE` | 1 |
| `human_misc` | `spit_name` | text | `` | 1 |
| `human_misc` | `spit_projectile` |  | `` | 1 |
| `regen` | `active_regen` | bool | `FALSE` | 1 |
| `regen` | `active_regen_delay` | num | `300` | 1 |

### `/obj`

| Feature (owned var) | Slot = field | Kind | Default | Wave |
|---|---|---|---|---|
| `(no feature yet)` | `being_shocked` | bool | `FALSE` | 0 |
| `(no feature yet)` | `burn_ended_by` | text | `` | 0 |
| `(no feature yet)` | `burn_fuel` | num | `0` | 0 |
| `(no feature yet)` | `burn_overlay` |  | `` | 0 |
| `(no feature yet)` | `burn_particle_type` |  | `` | 0 |
| `(no feature yet)` | `burning_particles` |  | `` | 0 |
| `(no feature yet)` | `custom_fire_overlay` |  | `` | 0 |
| `(no feature yet)` | `debris_amount` | num | `1` | 0 |
| `(no feature yet)` | `economic_department` | text | `` | 0 |
| `(no feature yet)` | `economic_export_value` | num | `0` | 0 |
| `(no feature yet)` | `economic_producer_account` | num | `0` | 0 |
| `(no feature yet)` | `economic_sale_invoice_id` | num | `0` | 0 |
| `(no feature yet)` | `micro_accepted_scale` | num | `0.5` | 0 |
| `(no feature yet)` | `obj_flags` | num | `CAN_BE_HIT` | 0 |

### `/obj/item`

| Feature (owned var) | Slot = field | Kind | Default | Wave |
|---|---|---|---|---|
| `(no feature yet)` | `ckeys_allowed_itemspawn` | list | `` | 0 |
| `(no feature yet)` | `cleandesc` | text | `` | 0 |
| `(no feature yet)` | `cleanname` | text | `` | 0 |
| `(no feature yet)` | `cleaving` | bool | `FALSE` | 0 |
| `(no feature yet)` | `clothing_channel_colors` | text | `` | 0 |
| `(no feature yet)` | `d_mult_old` | num | `1` | 0 |
| `(no feature yet)` | `digest_stage` | num | `` | 0 |
| `(no feature yet)` | `item_tf_spawn_allowed` | bool | `FALSE` | 0 |
| `(no feature yet)` | `mat_luminescence` | num | `0` | 0 |
| `(no feature yet)` | `mat_radioactivity` | num | `0` | 0 |
| `(no feature yet)` | `mat_toxicity` | num | `0` | 0 |
| `(no feature yet)` | `oldname` | text | `` | 0 |
| `(no feature yet)` | `tether_path` |  | `` | 0 |
| `(no feature yet)` | `trash_eatable` | bool | `TRUE` | 0 |
| `(no feature yet)` | `user_vars_remembered` | list | `` | 0 |
| `(no feature yet)` | `user_vars_to_edit` | list | `` | 0 |
| `(no feature yet)` | `warned_of_possession` | list | `` | 0 |
| `(no feature yet)` | `worn_layer` | num | `` | 0 |
| `(no feature yet)` | `zoom` | bool | `FALSE` | 0 |

### `/obj/machinery`

| Feature (owned var) | Slot = field | Kind | Default | Wave |
|---|---|---|---|---|
| `(no feature yet)` | `gas_dependency_wake_count` | num | `0` | 0 |
| `(no feature yet)` | `heat_output_now` | num | `0` | 0 |
| `(no feature yet)` | `material_component_manifest` | list | `` | 0 |
| `(no feature yet)` | `material_emp_resistance` | num | `0` | 0 |
| `(no feature yet)` | `power_init_complete` | bool | `FALSE` | 0 |
| `(no feature yet)` | `rebuilding` | bool | `` | 0 |
| `(no feature yet)` | `recursive_set` | bool | `FALSE` | 0 |
