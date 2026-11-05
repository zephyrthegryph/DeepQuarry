/// Sets stat tab `tab` of the mob's custom stat tabs to `contents` (the tabs are rebuilt every Stat(): update_misc_tabs()).
/proc/misc_tab_set(mob/M, tab, list/rows)
	var/list/tabs = STATE_GET(M, mob_misc, misc_tabs)
	if(!tabs)
		tabs = list()
		STATE_SET(M, mob_misc, misc_tabs, tabs)
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
