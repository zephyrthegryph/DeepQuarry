/*
 * Helper file for Exosuit / Mecha code.
 */

// Returns, at least, a usable target body position, for things like guns.

/obj/mecha/proc/get_pilot_zone_sel()
	var/mob/living/carbon/occupant = SLOT_ITEM(src, MECHA_SLOT_PILOT)
	if(!occupant || !occupant.zone_sel || occupant.stat)
		return BP_TORSO

	return occupant.zone_sel.selecting
