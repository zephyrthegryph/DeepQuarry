
/*
 * Patches. A subtype of pills, in order to inherit the possible future produceability within chem-masters, and dissolving.
 */

/obj/item/reagent_containers/pill/patch
	name = "patch"
	desc = "A patch."
	icon = 'icons/obj/chemical.dmi'
	icon_state = null
	item_state = "pill"

	base_state = "patch"

	max_transfer_amount = null
	w_class = ITEMSIZE_TINY
	slot_flags = SLOT_EARS
	volume = 60

	var/pierce_material = FALSE	// If true, the patch can be used through thick material.

/obj/item/reagent_containers/pill/patch/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	var/mob/living/L = user

	if(M == L)
		if(ishuman(M))
			var/mob/living/carbon/human/H = M
			var/obj/item/organ/external/affecting = H.get_organ(check_zone(L.zone_sel.selecting))
			if(!affecting)
				to_chat(user, span_warning("The limb is missing!"))
				return ITEM_INTERACT_FAILURE
			if(affecting.status >= ORGAN_ROBOT)
				to_chat(user, span_notice("\The [src] won't work on a robotic limb!"))
				return ITEM_INTERACT_FAILURE

			if(!H.can_inject(user, FALSE, L.zone_sel.selecting, pierce_material))
				to_chat(user, span_notice("\The [src] can't be applied through such a thick material!"))
				return ITEM_INTERACT_FAILURE

			to_chat(H, span_notice("\The [src] is placed on your [affecting]."))
			M.drop_from_inventory(src) //icon update
			if(reagents.total_volume)
				reagents.trans_to_mob(M, reagents.total_volume, CHEM_TOUCH)
			consume(src, user)
			return ITEM_INTERACT_SUCCESS

	else if(ishuman(M))
		var/mob/living/carbon/human/H = M
		var/obj/item/organ/external/affecting = H.get_organ(check_zone(L.zone_sel.selecting))
		if(!affecting)
			to_chat(user, span_warning("The limb is missing!"))
			return ITEM_INTERACT_FAILURE
		if(affecting.status >= ORGAN_ROBOT)
			to_chat(user, span_notice("\The [src] won't work on a robotic limb!"))
			return ITEM_INTERACT_FAILURE

		if(!H.can_inject(user, FALSE, L.zone_sel.selecting, pierce_material))
			to_chat(user, span_notice("\The [src] can't be applied through such a thick material!"))
			return ITEM_INTERACT_FAILURE

		act_message(user, src, others = span_warning("%U% attempts to place %T% onto [H]`s [affecting]."))

		user.setClickCooldown(user.get_attack_speed(src))
		om_task_start(/datum/om/task/timed/patch_apply_patch, user, M, receiver = src, H = H, affecting = affecting)
		return ITEM_INTERACT_SUCCESS

	return ITEM_INTERACT_FAILURE

/datum/om/task/timed/patch_apply_patch
	duration = 3 SECONDS
	complete_proc = /obj/item/reagent_containers/pill/patch/proc/apply_patch_done
	var/mob/living/carbon/human/H
	var/obj/item/organ/external/affecting

/obj/item/reagent_containers/pill/patch/proc/apply_patch_done(datum/om/task/timed/patch_apply_patch/task)
	var/mob/living/user = task.actor
	var/mob/living/carbon/human/H = task.H
	var/obj/item/organ/external/affecting = task.affecting
	user.drop_from_inventory(src) //icon update
	act_message(user, src, others = span_warning("%U% applies %T% to [H]."))

	var/contained = reagentlist()
	add_attack_logs(user,H,"Applied a patch containing [contained]")

	to_chat(H, span_notice("\The [src] is placed on your [affecting]."))
	H.drop_from_inventory(src) //icon update

	if(reagents.total_volume)
		reagents.trans_to_mob(H, reagents.total_volume, CHEM_TOUCH)	//CHEM_TOUCH
	consume(src, user)
