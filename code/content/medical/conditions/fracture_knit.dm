// A fracture that is knit without being set. Setting the bone (TREAT_BONE_SETTING: the set-bone step, bone gel, a bone setter) cures the
// fracture and the bone is straight. A bone repair mechanism (TREAT_BONE_REPAIR: osteodaxon) only knits what it finds: on a fracture that is
// still unset it knits the bone out of line, so the fracture becomes a /datum/affliction/malunion (trauma.dm) until a surgeon breaks it again
// (surgical_step/rebreak_bone). Setting cures the fracture outright, so a set bone has nothing left for osteodaxon to knit.

/// Only a strong enough source counts when it is continuous; an instant mend (osteodaxon's, dq_reagent_knit_fracture(O, TREAT_BONE_REPAIR)) always does.
#define FRACTURE_KNIT_MIN_LEVEL 0.5

/datum/affliction/untreated_fracture/receive_tagged_treatment(tag, amount, continuous = FALSE)
	if(tag != TREAT_BONE_REPAIR)
		return ..()
	if(continuous && amount < FRACTURE_KNIT_MIN_LEVEL)
		return 0
	return knit_crooked(amount)

/// The fracture heals out of line: the limb gets a malunion and the fracture is gone. Returns `amount` when it did.
/datum/affliction/untreated_fracture/proc/knit_crooked(amount)
	var/obj/item/organ/external/E = location
	if(!body || !istype(E) || E.is_robotic())
		return 0
	body.afflict(/datum/affliction/malunion, E)
	log_game("FRACTURE: [key_name(owner)]'s unset [E.name] knitted crooked.")
	cure()
	return amount
