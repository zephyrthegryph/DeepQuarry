/obj/item/stack/nanopaste
	name = "nanopaste"
	singular_name = "nanite swarm"
	desc = "A tube of paste containing swarms of repair nanites. Very effective in repairing robotic machinery."
	icon = 'icons/obj/stacks_vr.dmi'
	icon_state = "nanopaste"
	amount = 10
	max_amount = 10
	toolspeed = 0.75 //Used in surgery, shouldn't be the same speed as a normal screwdriver on mechanical organ repair.
	w_class = ITEMSIZE_SMALL
	no_variants = FALSE

/obj/item/stack/nanopaste/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!istype(M) || !istype(user))
		return ITEM_INTERACT_FAILURE
	if(istype(M,/mob/living/silicon/robot) && can_use(1))	//Repairing cyborgs; the repair itself is the robot_repair op when there is damage to mend
		var/mob/living/silicon/robot/R = M
		balloon_alert(user, "all [R]'s systems are nominal.")
		return ITEM_INTERACT_FAILURE

	if(ishuman(M))		//Repairing robolimbs
		var/mob/living/carbon/human/H = M
		var/obj/item/organ/external/S = H.get_organ(user.zone_sel.selecting)
		if(!S)
			balloon_alert(user, "no body part there to work on!")
			return ITEM_INTERACT_FAILURE

		if(S.organ_tag == BP_HEAD)
			if(H.get_equipped_item(SLOT_ID_HEAD) && istype(H.get_equipped_item(SLOT_ID_HEAD),/obj/item/clothing/head/helmet/space))
				balloon_alert(user, "you can't apply [src] through [H.get_equipped_item(SLOT_ID_HEAD)]!")
				return ITEM_INTERACT_FAILURE
		else
			if(H.get_equipped_item(SLOT_ID_SUIT) && istype(H.get_equipped_item(SLOT_ID_SUIT),/obj/item/clothing/suit/space))
				balloon_alert(user, "you can't apply [src] through [H.get_equipped_item(SLOT_ID_SUIT)]!")
				return ITEM_INTERACT_FAILURE

		if (S && (S.is_robotic()))
			if(!S.get_damage())
				balloon_alert(user, "nothing to fix here.")
				return ITEM_INTERACT_FAILURE
			else if((S.open < 2) && (S.get_trauma() + S.get_burn() >= S.min_broken_damage) && !repair_external)
				balloon_alert(user, "the damage is too extensive for this nanite swarm to handle.")
				return ITEM_INTERACT_FAILURE
			else if(can_use(1))
				user.setClickCooldown(user.get_attack_speed(src))
				// Nanites rebuild plating and wiring alike.
				var/restoration = S.open >= 2 ? restoration_internal : restoration_external
				perform_op(user, src, "repair_limb", src, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("patient" = H, "limb" = S, "restoration" = restoration))
				return ITEM_INTERACT_SUCCESS

/// Cyborgs are mended at the target (it must stay beside the user); a limb is mended by the stack's own op, started from attack() once the zone has been checked.
CAPABILITIES(/obj/item/stack/nanopaste)
	op("robot_repair", at_target(/mob/living/silicon/robot), answers(INTENT_USE, INTENT_ATTACK), when(req(PROC_REF(robot_needs_repair))), needs(req_adjacent()), wait(PROC_REF(robot_repair_time)), then(PROC_REF(robot_repaired)))
	op("repair_limb", ai(), takes("patient", "limb", "restoration"), wait(PROC_REF(limb_repair_time), keeps = HELD | TARGET_PRESENT | ALIVE | STAY), then(PROC_REF(repair_limb_done)))

/// There is plating or wiring to mend on the cyborg and a unit to spend.
/obj/item/stack/nanopaste/proc/robot_needs_repair(datum/act/op/A)
	var/mob/living/silicon/robot/R = A.target
	if(!read_once(can_use(1)))
		return MSG(req_failed)
	var/list/demand = read_once(R.treatment_demand(/datum/diagnostic_profile/robot_analyzer))
	return (!!(demand?[TREAT_PLATING_REPAIR] || demand?[TREAT_WIRING_REPAIR])) ? null : MSG(req_failed)

/obj/item/stack/nanopaste/proc/robot_repair_time(datum/act/op/A)
	return 7 * toolspeed

/obj/item/stack/nanopaste/proc/robot_repaired(datum/act/op/A)
	var/mob/living/silicon/robot/R = A.target
	var/mob/living/user = A.actor
	R.mend(TREAT_PLATING_REPAIR, 15)
	R.mend(TREAT_WIRING_REPAIR, 15)
	use(1)
	user.balloon_alert_visible("\the [user] applied some [src] on [R]'s damaged areas.",\
	"you apply some [src] at [R]'s damaged areas.")
	return OP_OK

/obj/item/stack/nanopaste/proc/limb_repair_time(datum/act/op/A)
	return 5 * toolspeed

/obj/item/stack/nanopaste/proc/repair_limb_done(datum/act/op/A)
	var/mob/living/user = A.actor
	var/mob/living/carbon/human/H = A.arg("patient")
	var/obj/item/organ/external/S = A.arg("limb")
	var/restoration = A.arg("restoration")
	if(QDELETED(H) || QDELETED(S) || !can_use(1))
		return OP_FAILED
	if(restoration)
		H.mend(TREAT_PLATING_REPAIR, restoration, S.organ_tag)
		H.mend(TREAT_WIRING_REPAIR, restoration, S.organ_tag)
	use(1)
	user.balloon_alert_visible("\the [user] applies some nanite paste on [user != H ? "[H]'s [S.name]" : "[S]"] with [src].",\
	"you apply some nanite paste on [user == H ? "your" : "[H]'s"] [S.name].")
	return OP_OK

/obj/item/stack/nanopaste
	var/restoration_external = 5
	var/restoration_internal = 20
	var/repair_external = FALSE
	var/mech_repair = 10

/obj/item/stack/nanopaste/advanced
	name = "advanced nanopaste"
	singular_name = "advanced nanite swarm"
	desc = "A tube of paste containing swarms of repair nanites. Very effective in repairing robotic machinery. These ones are capable of restoring condition even of most thrashed robotic parts"
	icon = 'icons/obj/stacks_vr.dmi'
	icon_state = "adv_nanopaste"
	restoration_external = 10
	repair_external = TRUE
	mech_repair = 20
