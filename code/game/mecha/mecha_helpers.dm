/*
 * Helper file for Exosuit / Mecha code.
 */

// Returns, at least, a usable target body position, for things like guns.

/obj/mecha/proc/get_pilot_zone_sel()
	var/mob/living/carbon/occupant = src?.slot_item(MECHA_SLOT_PILOT)
	if(!occupant || !occupant.zone_sel || occupant.stat)
		return BP_TORSO

	return occupant.zone_sel.selecting

/// Whether the pilot (a mob in MECHA_SLOT_PILOT) has combat mode on (no variant held); the pilot's posture as mech state. FALSE with no pilot.
/obj/mecha/proc/pilot_is_harming()
	var/mob/pilot = slot_item(MECHA_SLOT_PILOT)
	return ismob(pilot) && pilot.combat_mode && !pilot.attack_variant

/// Whether the pilot (a mob in MECHA_SLOT_PILOT) is using the Disarm variant. FALSE with no pilot.
/obj/mecha/proc/pilot_is_disarming()
	var/mob/pilot = slot_item(MECHA_SLOT_PILOT)
	return ismob(pilot) && pilot.attack_variant == ATTACK_VARIANT_DISARM
