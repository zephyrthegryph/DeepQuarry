// INTERIM mob slot declarations (roadmap C3). Replaced wholesale when the body
// rewrite declares slots on its /datum/body plans: delete this file and have
// the mobs' slot_def_types() / slot_def_key() read the plan instead.
//
// What the permanent inventory code (code/modules/mob/inventory.dm) needs from
// whatever replaces this file:
//   - an interior slot, id CONTAINER_SLOT_INTERIOR, the default, for organs,
//     implants and anything else inside the mob;
//   - one slot per equip slot the plan has, id SLOT_ID_*, capacity one item
//     (SLOT_CAPACITY_COUNT, 1), accepts = the matching /datum/predicate/equip_slot
//     (dq_equip_slot_predicate()), refusing when the body part isn't there;
//   - robots: SLOT_ID_MODULE(1..3);
//   - drop_policy SLOT_DROP_HOLDER on all of them for now: mob Destroy() still
//     decides what happens to a mob's contents.
// Species gating (hud.equip_slots) and missing limbs are checked in the slot's
// refusal() here; with body plans they become which slots the plan has.

// ---- Definitions ----

/datum/slot_def/mob_interior
	id = CONTAINER_SLOT_INTERIOR
	name = "inside"
	exposure = SLOT_EXPOSURE_INTERNAL
	is_default = TRUE
	drop_policy = SLOT_DROP_HOLDER

/// One item on a mob, in slot_* `slot_num`.
/datum/slot_def/mob_equip
	id = "mob_equip"
	exposure = SLOT_EXPOSURE_EXTERNAL
	capacity_model = SLOT_CAPACITY_COUNT
	capacity = 1
	drop_policy = SLOT_DROP_HOLDER
	/// slot_* number.
	var/slot_num
	/// Refused when the species' HUD has no such slot.
	var/species_gated = TRUE
	/// Refused when the body part it hangs on is missing (has_organ_for_slot()).
	var/needs_organ = TRUE

/datum/slot_def/mob_equip/New()
	..()
	if(slot_num && !accepts)
		var/datum/predicate/P = dq_equip_slot_predicate(slot_num)
		accepts = P?.type

/datum/slot_def/mob_equip/refusal(atom/holder, atom/movable/thing, mob/actor)
	if(!isitem(thing))
		return "only items go there"
	if(ishuman(holder))
		var/mob/living/carbon/human/H = holder
		if(species_gated && H.species && !(slot_num in dq_equip_slots_of(H)))
			return "you have nowhere to wear it"
		if(needs_organ && !H.has_organ_for_slot(slot_num))
			return "you have nothing to wear it on"
	return ..()

/datum/slot_def/mob_equip/hand
	species_gated = FALSE
	needs_organ = FALSE

/datum/slot_def/mob_equip/hand/left
	id = SLOT_ID_L_HAND
	name = "left hand"
	slot_num = slot_l_hand

/datum/slot_def/mob_equip/hand/right
	id = SLOT_ID_R_HAND
	name = "right hand"
	slot_num = slot_r_hand

/datum/slot_def/mob_equip/back
	id = SLOT_ID_BACK
	name = "back"
	slot_num = slot_back

/datum/slot_def/mob_equip/mask
	id = SLOT_ID_WEAR_MASK
	name = "mask"
	slot_num = slot_wear_mask

/datum/slot_def/mob_equip/handcuffed
	id = SLOT_ID_HANDCUFFED
	name = "handcuffs"
	slot_num = slot_handcuffed

/datum/slot_def/mob_equip/legcuffed
	id = SLOT_ID_LEGCUFFED
	name = "legcuffs"
	slot_num = slot_legcuffed

/datum/slot_def/mob_equip/belt
	id = SLOT_ID_BELT
	name = "belt"
	slot_num = slot_belt

/datum/slot_def/mob_equip/wear_id
	id = SLOT_ID_WEAR_ID
	name = "ID"
	slot_num = slot_wear_id

/datum/slot_def/mob_equip/s_store
	id = SLOT_ID_S_STORE
	name = "suit storage"
	slot_num = slot_s_store

/datum/slot_def/mob_equip/l_store
	id = SLOT_ID_L_STORE
	name = "left pocket"
	slot_num = slot_l_store

/datum/slot_def/mob_equip/r_store
	id = SLOT_ID_R_STORE
	name = "right pocket"
	slot_num = slot_r_store

/datum/slot_def/mob_equip/glasses
	id = SLOT_ID_GLASSES
	name = "eyes"
	slot_num = slot_glasses

/datum/slot_def/mob_equip/gloves
	id = SLOT_ID_GLOVES
	name = "hands"
	slot_num = slot_gloves

/datum/slot_def/mob_equip/head
	id = SLOT_ID_HEAD
	name = "head"
	slot_num = slot_head

/datum/slot_def/mob_equip/shoes
	id = SLOT_ID_SHOES
	name = "feet"
	slot_num = slot_shoes

/datum/slot_def/mob_equip/wear_suit
	id = SLOT_ID_WEAR_SUIT
	name = "suit"
	slot_num = slot_wear_suit

/datum/slot_def/mob_equip/w_uniform
	id = SLOT_ID_W_UNIFORM
	name = "uniform"
	slot_num = slot_w_uniform

/datum/slot_def/mob_equip/l_ear
	id = SLOT_ID_L_EAR
	name = "left ear"
	slot_num = slot_l_ear

/datum/slot_def/mob_equip/r_ear
	id = SLOT_ID_R_EAR
	name = "right ear"
	slot_num = slot_r_ear

/// An active robot module (the old module_state_1..3).
/datum/slot_def/robot_module
	exposure = SLOT_EXPOSURE_EXTERNAL
	capacity_model = SLOT_CAPACITY_COUNT
	capacity = 1
	drop_policy = SLOT_DROP_HOLDER

/datum/slot_def/robot_module/one
	id = SLOT_ID_MODULE_1
	name = "module 1"

/datum/slot_def/robot_module/two
	id = SLOT_ID_MODULE_2
	name = "module 2"

/datum/slot_def/robot_module/three
	id = SLOT_ID_MODULE_3
	name = "module 3"

// ---- Which mobs have which ----
// Keyed by type (the default slot_def_key()). With body plans the key becomes
// "[type]|[plan]".

/mob/living/slot_def_types()
	var/static/list/types = list(
		/datum/slot_def/mob_interior,
		/datum/slot_def/mob_equip/hand/left,
		/datum/slot_def/mob_equip/hand/right,
	)
	return types

/mob/living/carbon/slot_def_types()
	var/static/list/types = list(
		/datum/slot_def/mob_interior,
		/datum/slot_def/mob_equip/hand/left,
		/datum/slot_def/mob_equip/hand/right,
		/datum/slot_def/mob_equip/handcuffed,
		/datum/slot_def/mob_equip/legcuffed,
	)
	return types

/mob/living/carbon/human/slot_def_types()
	var/static/list/types = list(
		/datum/slot_def/mob_interior,
		/datum/slot_def/mob_equip/hand/left,
		/datum/slot_def/mob_equip/hand/right,
		/datum/slot_def/mob_equip/back,
		/datum/slot_def/mob_equip/wear_suit,
		/datum/slot_def/mob_equip/w_uniform,
		/datum/slot_def/mob_equip/belt,
		/datum/slot_def/mob_equip/wear_id,
		/datum/slot_def/mob_equip/head,
		/datum/slot_def/mob_equip/mask,
		/datum/slot_def/mob_equip/glasses,
		/datum/slot_def/mob_equip/l_ear,
		/datum/slot_def/mob_equip/r_ear,
		/datum/slot_def/mob_equip/gloves,
		/datum/slot_def/mob_equip/shoes,
		/datum/slot_def/mob_equip/s_store,
		/datum/slot_def/mob_equip/l_store,
		/datum/slot_def/mob_equip/r_store,
		/datum/slot_def/mob_equip/handcuffed,
		/datum/slot_def/mob_equip/legcuffed,
	)
	return types

/mob/living/silicon/robot/slot_def_types()
	var/static/list/types = list(
		/datum/slot_def/mob_interior,
		/datum/slot_def/robot_module/one,
		/datum/slot_def/robot_module/two,
		/datum/slot_def/robot_module/three,
	)
	return types
