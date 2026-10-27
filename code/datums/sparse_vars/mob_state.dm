// Rare and scratch per-instance state of mobs: sparse slots (code/engine/declare/sparse_slots.dm), nothing on /mob until one is set.
// The default each slot reads as is the one the var it replaced was declared with (sparse_get_or(M, slot, default)); a write of null clears it.
// Read and write them through sparse_get() / sparse_get_or() / sparse_set(), never through a var of the same name.

// /mob
sparse(/mob, last_emote_summary, type = text)
sparse(/mob, registered_z, type = num)
sparse(/mob, inertia_dir, type = num)
sparse(/mob, name_archive, type = text)
sparse(/mob, lastattacker_name, type = text)
sparse(/mob, lastattacker_key, type = text)
sparse(/mob, floatiness, type = num)
sparse(/mob, damageoverlaytemp, type = num)
sparse(/mob, bhunger, type = num)
sparse(/mob, lastareachange, type = num)
sparse(/mob, facing_dir, type = num)
sparse(/mob, lastKnownIP, type = text)
// The computer id the mob's last client had, kept for the ban and multikey checks while it is offline.
sparse(/mob, computer_id, type = text)
sparse(/mob, skincmds, type = list)
sparse(/mob, ajourn, type = num)
sparse(/mob, is_slipping, type = bool)
sparse(/mob, skip_buckled_move_redirect, type = bool)
sparse(/mob, get_rig_stats, type = num)
sparse(/mob, m_int, type = text)
sparse(/mob, vantag_hud, type = num)
// Names of the genes switched on in this mob's DNA (/datum/gene/proc/mark_active).
sparse(/mob, active_genes, type = list)
sparse(/mob, narsimage, type = /image)
sparse(/mob, narglow, type = /image)
sparse(/mob, riftimage, type = /image)

// /mob/living
sparse(/mob/living, adminbus_eat_minerals, type = bool)
// Reagent id -> addiction counter, for every addiction tracked (built up, active or in withdrawal): mob/living/carbon/addictions.dm.
sparse(/mob/living/carbon, addiction_counters, type = list)
sparse(/mob/living, body_effect_serial, type = num)
// Body effect type -> list of timed-stack names (body_effect_stack_names()).
sparse(/mob/living, body_effect_timers, type = list)
sparse(/mob/living, last_instability, type = num)
sparse(/mob/living, melee_swing_serial, type = num)
sparse(/mob/living, ventcrawl_layer, type = num)
sparse(/mob/living, churn_count, type = num)
sparse(/mob/living, skin_reagent, type = text)
sparse(/mob/living, tf_form_holds_key, type = bool)
sparse(/mob/living, composition_reagent_quantity, type = num)
sparse(/mob/living, disability_death_time, type = num)
sparse(/mob/living, disability_gut_pressure, type = num)
sparse(/mob/living, slosh_chance, type = num)
sparse(/mob/living, slosh_steps, type = num)
sparse(/mob/living, slosh_volume, type = num)
sparse(/mob/living, footstep_vary, type = bool)
sparse(/mob/living, footstep_steps, type = num)
sparse(/mob/living, mute_entry, type = bool)
sparse(/mob/living, trash_catching, type = bool)
sparse(/mob/living, trait_injection_verb, type = text)
sparse(/mob/living, trait_injection_reagents, type = list)
sparse(/mob/living, digestion_in_progress, type = bool)
sparse(/mob/living, photosynthesis_boost, type = num)
sparse(/mob/living, drain_finalized, type = num)
sparse(/mob/living, holder_default, type = text)
sparse(/mob/living, custom_link, type = text)
sparse(/mob/living, eggs, type = num)
sparse(/mob/living, failed_last_breath, type = num)
sparse(/mob/living, summoned, type = bool)

// /mob/living/carbon
sparse(/mob/living/carbon, last_taste_text, type = text)
sparse(/mob/living/carbon, germs_rolled_at, type = num)
sparse(/mob/living/carbon, synth_reag_processing, type = bool)
sparse(/mob/living/carbon, breath_cycle, type = num)

// /mob/living/carbon/human
sparse(/mob/living/carbon/human, nutrition_drained_at, type = num)
sparse(/mob/living/carbon/human, dq_last_neural_load, type = num)
sparse(/mob/living/carbon/human, dq_last_radiation, type = num)
sparse(/mob/living/carbon/human, dq_last_bodytemperature, type = num)
sparse(/mob/living/carbon/human, nutrition_hidden, type = bool)
sparse(/mob/living/carbon/human, chemical_darksight, type = num)
sparse(/mob/living/carbon/human, environment_steady, type = bool)
sparse(/mob/living/carbon/human, gender_change_cooldown, type = num)
sparse(/mob/living/carbon/human, changeling_locked, type = bool)
sparse(/mob/living/carbon/human, can_defib, type = num)
sparse(/mob/living/carbon/human, damage_multiplier, type = num)

// /mob
sparse(/mob, autowhisper_mode, type = text)
sparse(/mob, away_from_keyboard, type = bool)
sparse(/mob, died_in_vr, type = bool)
sparse(/mob, digitalcamo, type = num)
sparse(/mob, disconnect_time, type = num)
sparse(/mob, dizzy_was_resting, type = bool)
sparse(/mob, forbid_seeing_deadchat, type = bool)
sparse(/mob, hive_lang_range, type = num)
sparse(/mob, jittery_was_resting, type = bool)
sparse(/mob, manual_afk, type = bool)
sparse(/mob, other_mobs, type = num)
sparse(/mob, updating_fullness, type = bool)

// /mob/living
sparse(/mob/living, absorbing_prey, type = num)
sparse(/mob/living, autofire_delay, type = num)
sparse(/mob/living, autofire_params, type = text)
sparse(/mob/living, liquidbelly_visuals, type = bool)
sparse(/mob/living, melee_swing_resolving, type = bool)
sparse(/mob/living, omen_incidents, type = num)
sparse(/mob/living, omen_luck, type = num)
sparse(/mob/living, omen_safe_disposals, type = bool)
sparse(/mob/living, omen_vorish, type = bool)
sparse(/mob/living, passtable_crawl_checked, type = bool)
sparse(/mob/living, passtable_reset, type = bool)
sparse(/mob/living, pickup_active, type = bool)
sparse(/mob/living, rad_countdown_minimum, type = num)
sparse(/mob/living, revival_in_progress, type = bool)
sparse(/mob/living, trait_injection_amount, type = num)
sparse(/mob/living, trait_injection_selected)
sparse(/mob/living, updating_cult_vision, type = num)

// /mob/living/carbon
sparse(/mob/living/carbon, pose_move, type = bool)

// /mob/living/carbon/human
sparse(/mob/living/carbon/human, active_regen, type = bool)
sparse(/mob/living/carbon/human, active_regen_delay, type = num)
sparse(/mob/living/carbon/human, health_doll_key, type = text)
sparse(/mob/living/carbon/human, spit_name, type = text)
sparse(/mob/living/carbon/human, heartbeat, type = num)
sparse(/mob/living/carbon/human, spit_projectile)
sparse(/mob/living/carbon/human, speech_sound_enabled, type = bool)

// /mob
sparse(/mob, suiciding, type = num)

// /mob/living
sparse(/mob/living, capture_caught, type = bool)
sparse(/mob/living, prey_controlled, type = bool)
sparse(/mob/living, touch_reaction_flags, type = num)

// base_vars wave 3
sparse(/mob, is_floating, type = num)
sparse(/mob, muffled, type = bool)
sparse(/mob, autowhisper, type = bool)
sparse(/mob, lying_prev, type = num)
sparse(/mob, seer, type = num)
sparse(/mob, in_throw_mode, type = num)
sparse(/mob, ventcraw_item_admin_allow, type = list)
sparse(/mob, is_motion_tracking, type = bool)
sparse(/mob, wants_to_see_motion_echos, type = bool)
sparse(/mob, voice_freq, type = num)
sparse(/mob, emote_sound_mode)
sparse(/mob/living, flight_vore, type = bool)
sparse(/mob/living, tod, type = text)
sparse(/mob/living, is_swinging, type = bool)
sparse(/mob/living, is_ventcrawling, type = bool)
sparse(/mob/living, weight_gain, type = num)
sparse(/mob/living, weight_loss, type = num)
sparse(/mob/living, vore_egg_type, type = text)
sparse(/mob/living, stuffing_feeder, type = bool)
sparse(/mob/living, appendage_alt_setting, type = bool)
sparse(/mob/living/carbon, dream_wait, type = num)
sparse(/mob/living/carbon, pose, type = text)
sparse(/mob/living/carbon, current_dream, type = /datum/dream)
sparse(/mob/living/carbon/human, markings_len, type = num)
sparse(/mob/living/carbon/human, body_writing, type = list)
sparse(/mob/living/carbon/human, resleeve_lock)

// Weak slots: they name another mob or atom by handle, pin nothing and read null once it is gone (sparse_ref(), code/engine/declare/sparse_slots.dm).
sparse(/mob, lastattacker, type = weak)
sparse(/mob, LAssailant, type = weak)
sparse(/mob, teleop, type = weak)
sparse(/mob/living, autofire_target, type = weak)

// base_vars wave 9
sparse(/mob, progressbars, type = list)
sparse(/mob, misc_tabs, type = list)
sparse(/mob, spont_belly_front, type = text)
sparse(/mob, spont_belly_rear, type = text)
sparse(/mob, spont_belly_left, type = text)
sparse(/mob, spont_belly_right, type = text)
sparse(/mob/living, temp_languages, type = list)

/// Sets stat tab `tab` of the mob's custom stat tabs to `contents` (the tabs are rebuilt every Stat(): update_misc_tabs()).
/proc/misc_tab_set(mob/M, tab, list/rows)
	var/list/tabs = sparse_get(M, misc_tabs)
	if(!tabs)
		tabs = sparse_set(M, misc_tabs, list())
	tabs[tab] = rows

// base_vars wave 11: rare numeric state of a mob. Each reads 0 while unset and a write of 0 clears it. (losebreath, read by every breathing step, lives on the physiology.)
sparse(/mob, disabilities, type = num)
sparse(/mob, accumulated_rads, type = num)

/// The mob's disability bitfield (NEARSIGHTED, CLUMSY, BLIND, ...): 0 for nearly every mob, so it is a slot.
/mob/proc/disabilities()
	return sparse_get_or(src, disabilities, 0)

/mob/proc/set_disabilities(flags)
	return sparse_set_or(src, disabilities, flags, 0)

/// Adds the disability flags `flags` to the mob.
/mob/proc/add_disabilities(flags)
	return set_disabilities(disabilities() | flags)

/// Takes the disability flags `flags` off the mob.
/mob/proc/remove_disabilities(flags)
	return set_disabilities(disabilities() & ~flags)

/// The long-term radiation dose that settles out of the acute one (radiation is the acute dose; the writers are in code/modules/body/injury.dm).
/mob/proc/accumulated_rads()
	return sparse_get_or(src, accumulated_rads, 0)

/mob/proc/set_accumulated_rads(amount)
	return sparse_set_or(src, accumulated_rads, amount, 0)
