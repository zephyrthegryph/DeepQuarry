// A fracture that is knit without being set. Setting the bone (TREAT_BONE_SETTING: the set-bone step, bone gel, a bone setter) cures the
// fracture and the bone is straight. A bone repair mechanism (TREAT_BONE_REPAIR: osteodaxon) only knits what it finds: on a fracture that is
// still unset it knits the bone out of line, so the fracture becomes a /datum/affliction/malunion (trauma.dm) until a surgeon breaks it again
// (surgical_step/rebreak_bone). Setting cures the fracture outright, so a set bone has nothing left for osteodaxon to knit.

/// Only a strong enough source counts when it is continuous; an instant mend (osteodaxon's, dq_reagent_knit_fracture(O, TREAT_BONE_REPAIR)) always does.
#define FRACTURE_KNIT_MIN_LEVEL 0.5

/// The mechanisms that knit an unset fracture out of line (TREAT_BONE_REPAIR), and what the limb gets instead (`crooked_into`). The medical book reads both
/// to tell the reader what a bone-knitting drug does to an unset fracture.
/datum/affliction/untreated_fracture
	var/static/list/knits_crooked_by = list(TREAT_BONE_REPAIR)
	var/crooked_into = /datum/affliction/malunion
	/// The least level of such a mechanism that counts as a drug in the blood (an instant mend always knits).
	var/knit_min_level = FRACTURE_KNIT_MIN_LEVEL


/datum/affliction/untreated_fracture/receive_tagged_treatment(tag, amount, continuous = FALSE)
	if(!(tag in knits_crooked_by))
		return ..()
	if(continuous && amount < knit_min_level)
		return 0
	return knit_crooked(amount)

/// The fracture heals out of line: the limb gets a malunion and the fracture is gone. Returns `amount` when it did.
/datum/affliction/untreated_fracture/proc/knit_crooked(amount)
	var/obj/item/organ/external/E = location
	if(!body || !istype(E) || E.is_robotic())
		return 0
	body.afflict(crooked_into, E)
	log_game("FRACTURE: [key_name(owner)]'s unset [E.name] knitted crooked.")
	cure()
	return amount
