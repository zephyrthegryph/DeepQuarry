// Rare and scratch per-instance state of mobs: sparse slots (code/engine/declare/sparse_slots.dm), nothing on /mob until one is set.
// The default each slot reads as is the one the var it replaced was declared with (sparse_get_or(M, slot, default)); a write of null clears it.
// Read and write them through sparse_get() / sparse_get_or() / sparse_set(), never through a var of the same name.

// /mob
// The computer id the mob's last client had, kept for the ban and multikey checks while it is offline.
sparse(/mob, skincmds, type = list)
// Names of the genes switched on in this mob's DNA (/datum/gene/proc/mark_active).
sparse(/mob, active_genes, type = list)
// The sounds the mob's speech and emotes play (a pick from this list); set by preferences or login.
sparse(/mob, voice_sounds_list, type = list)
// The mob's own log, message type -> list of timestamped lines (log_message(); the admin player-log viewer reads it). Unused when database_logging is on.
sparse(/mob, logging, type = list)

// /mob/living
// Reagent id -> addiction counter, for every addiction tracked (built up, active or in withdrawal): mob/living/carbon/addictions.dm.
sparse(/mob/living/carbon, addiction_counters, type = list)
// Body weight in pounds for the weightgain system; reads as DEFAULT_MOB_WEIGHT when unset (sparse_get_or / sparse_set_or).
// Body effect type -> list of timed-stack names (body_effect_stack_names()).
sparse(/mob/living, body_effect_timers, type = list)
sparse(/mob/living, trait_injection_reagents, type = list)

// /mob/living/carbon

// /mob/living/carbon/human

// /mob

// /mob/living

// /mob/living/carbon

// /mob/living/carbon/human

// /mob

// /mob/living

// base_vars wave 3
sparse(/mob, ventcraw_item_admin_allow, type = list)
sparse(/mob/living/carbon, dream_fragments, type = list)
sparse(/mob/living/carbon/human, body_writing, type = list)

// Weak slots: they name another mob or atom by handle, pin nothing and read null once it is gone (sparse_ref(), code/engine/declare/sparse_slots.dm).
sparse(/mob, lastattacker, type = weak)
sparse(/mob, LAssailant, type = weak)
sparse(/mob, teleop, type = weak)
sparse(/mob/living, autofire_target, type = weak)

// base_vars wave 9
sparse(/mob, progressbars, type = list)
sparse(/mob, misc_tabs, type = list)
sparse(/mob/living, temp_languages, type = list)

/// Sets stat tab `tab` of the mob's custom stat tabs to `contents` (the tabs are rebuilt every Stat(): update_misc_tabs()).
/proc/misc_tab_set(mob/M, tab, list/rows)
	var/list/tabs = sparse_get(M, misc_tabs)
	if(!tabs)
		tabs = sparse_set(M, misc_tabs, list())
	tabs[tab] = rows

// base_vars wave 11: rare numeric state of a mob. Each reads 0 while unset and a write of 0 clears it. (losebreath, read by every breathing step, lives on the physiology.)

/// The mob's disability bitfield (NEARSIGHTED, CLUMSY, BLIND, ...): 0 for nearly every mob, so it is a slot.
/mob/proc/disabilities()
	return STATE_GET(src, mob_misc, disabilities)

/mob/proc/set_disabilities(flags)
	STATE_SET(src, mob_misc, disabilities, flags)
	return flags

/// Adds the disability flags `flags` to the mob.
/mob/proc/add_disabilities(flags)
	return set_disabilities(disabilities() | flags)

/// Takes the disability flags `flags` off the mob.
/mob/proc/remove_disabilities(flags)
	return set_disabilities(disabilities() & ~flags)

/// The long-term radiation dose that settles out of the acute one (radiation is the acute dose; the writers are in code/modules/body/injury.dm).
/mob/proc/accumulated_rads()
	return STATE_GET(src, mob_misc, accumulated_rads)

/mob/proc/set_accumulated_rads(amount)
	STATE_SET(src, mob_misc, accumulated_rads, amount)
	return amount

// A bed or nest raising its buckled mob (the old /atom/movable old_y): added to default_pixel_y as the offset a shake or float returns to.
