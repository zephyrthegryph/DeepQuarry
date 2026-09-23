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
	if(istype(M,/mob/living/silicon/robot) && can_use(1))	//Repairing cyborgs
		var/mob/living/silicon/robot/R = M
		if(R.injury_load(INJURY_CATEGORY_PHYSICAL) || R.injury_load(INJURY_CATEGORY_THERMAL))
			if(do_after(user, 7 * toolspeed, target = R))
				R.mend(TREAT_PLATING_REPAIR, 15)
				R.mend(TREAT_WIRING_REPAIR, 15)
				use(1)
				user.balloon_alert_visible("\the [user] applied some [src] on [R]'s damaged areas.",\
				"you apply some [src] at [R]'s damaged areas.")
				return ITEM_INTERACT_SUCCESS
		else
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
			if(H.get_equipped_item(SLOT_ID_WEAR_SUIT) && istype(H.get_equipped_item(SLOT_ID_WEAR_SUIT),/obj/item/clothing/suit/space))
				balloon_alert(user, "you can't apply [src] through [H.get_equipped_item(SLOT_ID_WEAR_SUIT)]!")
				return ITEM_INTERACT_FAILURE

		if (S && (S.robotic >= ORGAN_ROBOT))
			if(!S.get_damage())
				balloon_alert(user, "nothing to fix here.")
				return ITEM_INTERACT_FAILURE
			else if((S.open < 2) && (S.get_trauma() + S.get_burn() >= S.min_broken_damage) && !repair_external)
				balloon_alert(user, "the damage is too extensive for this nanite swarm to handle.")
				return ITEM_INTERACT_FAILURE
			else if(can_use(1))
				user.setClickCooldown(user.get_attack_speed(src))
				// Nanites rebuild plating and wiring alike.
				var/restoration = 0
				if(S.open >= 2)
					if(do_after(user, 5 * toolspeed, target = S))
						restoration = restoration_internal
				else if(do_after(user, 5 * toolspeed, target = S))
					restoration = restoration_external
				if(restoration)
					H.mend(TREAT_PLATING_REPAIR, restoration, S.organ_tag)
					H.mend(TREAT_WIRING_REPAIR, restoration, S.organ_tag)
				use(1)
				user.balloon_alert_visible("\the [user] applies some nanite paste on [user != M ? "[M]'s [S.name]" : "[S]"] with [src].",\
				"you apply some nanite paste on [user == M ? "your" : "[M]'s"] [S.name].")
				return ITEM_INTERACT_SUCCESS


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
