/obj/item/stack/medical
	name = "medical pack"
	singular_name = "medical pack"
	icon = 'icons/obj/stacks.dmi'
	amount = 10
	max_amount = 10
	w_class = ITEMSIZE_SMALL
	throw_speed = 4
	throw_range = 20
	var/heal_brute = 0
	var/heal_burn = 0
	var/apply_sounds
	drop_sound = SFX_ITEMS_DROP_CARDBOARDBOX
	pickup_sound = SFX_ITEMS_PICKUP_CARDBOARDBOX

	var/upgrade_to	// The type path this stack can be upgraded to.

/obj/item/stack/medical/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!iscarbon(M))
		balloon_alert(user, "\the [src] cannot be applied to [M]!")
		return ITEM_INTERACT_FAILURE

	if (!user.IsAdvancedToolUser())
		balloon_alert(user, "you don't have the dexterity to do this!")
		return ITEM_INTERACT_FAILURE

	var/available = get_amount()
	if(!available)
		balloon_alert(user, "not enough [uses_charge ? "charge" : "items"] left to use that!")
		return ITEM_INTERACT_FAILURE

	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		var/obj/item/organ/external/affecting = H.get_organ(user.zone_sel.selecting)

		if(!affecting)
			balloon_alert(user, "no body part there to work on!")
			return ITEM_INTERACT_FAILURE

		if(affecting.organ_tag == BP_HEAD)
			if(H.get_equipped_item(SLOT_ID_HEAD) && istype(H.get_equipped_item(SLOT_ID_HEAD),/obj/item/clothing/head/helmet/space))
				balloon_alert(user, "you can't apply [src] through [H.get_equipped_item(SLOT_ID_HEAD)]!")
				return ITEM_INTERACT_FAILURE
		else
			if(H.get_equipped_item(SLOT_ID_SUIT) && istype(H.get_equipped_item(SLOT_ID_SUIT),/obj/item/clothing/suit/space))
				balloon_alert(user, "you can't apply [src] through [H.get_equipped_item(SLOT_ID_SUIT)]!")
				return ITEM_INTERACT_FAILURE

		if(affecting.robotic == ORGAN_ROBOT)
			balloon_alert(user, "this isn't useful at all on a robotic limb.")
			return ITEM_INTERACT_FAILURE

		if(affecting.robotic >= ORGAN_LIFELIKE)
			balloon_alert(user, "you apply the [src], but it seems to have no effect...")
			use(1)
			return ITEM_INTERACT_FAILURE

		H.UpdateDamageIcon()

	else
		if(heal_brute)
			M.mend(TREAT_TISSUE_REPAIR, heal_brute / 2)
		if(heal_burn)
			M.mend(TREAT_BURN_CARE, heal_burn / 2)
		user.balloon_alert_visible( \
			"[M] has been applied with [src] by [user].", \
			"you apply \the [src] to [M]." \
		)
		use(1)
		if(user != M && department_for_mob(user) == DEPARTMENT_MEDICAL)
			charge_mob_for_department_service(M, DEPARTMENT_MEDICAL, 2, "Medical treatment with [name]", user.real_name)
		return ITEM_INTERACT_SUCCESS

	if(user != M && department_for_mob(user) == DEPARTMENT_MEDICAL)
		charge_mob_for_department_service(M, DEPARTMENT_MEDICAL, 2, "Medical treatment with [name]", user.real_name)
	return ITEM_INTERACT_SUCCESS

// ---- Timed wound treatment: one wound per timed action, in order.

/// Whether this stack still has work to do on wound W.
/obj/item/stack/medical/proc/wound_needs_treatment(datum/affliction/wound/W)
	return !W.internal && !W.bandaged

/// Whether the stack stops after `amount` wounds.
/obj/item/stack/medical/proc/wound_limited_by_amount()
	return TRUE

/obj/item/stack/medical/proc/wound_treat_delay(datum/affliction/wound/W)
	return W.damage / 5

/// Someone else finished the job during the wait.
/obj/item/stack/medical/proc/wound_already_treated(mob/living/carbon/human/H, mob/living/user, obj/item/organ/external/affecting)
	if(affecting.is_bandaged()) // We do a second check after the delay, in case it was bandaged after the first check.
		balloon_alert(user, "[H]'s [affecting.name] is already bandaged.")
		return TRUE
	return FALSE

/// Treats W; returns the new count of stack units used.
/obj/item/stack/medical/proc/apply_wound_treatment(datum/affliction/wound/W, mob/living/carbon/human/H, mob/living/user, obj/item/organ/external/affecting, used)
	W.receive_tagged_treatment(TREAT_WOUND_PACKING, 1)
	playsound(src, apply_sounds, 25)
	return used + 1

/obj/item/stack/medical/proc/wound_treat_step(mob/living/carbon/human/H, mob/living/user, obj/item/organ/external/affecting, list/wounds, index, used, available)
	var/datum/affliction/wound/W
	while(index <= length(wounds))
		var/datum/affliction/wound/candidate = wounds[index]
		if(!QDELETED(candidate) && wound_needs_treatment(candidate))
			W = candidate
			break
		index++
	if(!W || (wound_limited_by_amount() && used == amount))
		wound_treat_finish(H, user, affecting, used)
		return
	task_start(/datum/task/timed/medical_wound_treat, user, affecting, duration = wound_treat_delay(W), H = H, wounds = wounds, index = index, used = used, available = available)

/obj/item/stack/medical/proc/wound_treat_interrupted(datum/task/timed/medical_wound_treat/task)
	var/mob/living/carbon/human/H = task.H
	var/mob/living/user = task.actor
	var/obj/item/organ/external/affecting = task.target
	var/used = task.used
	balloon_alert(user, "stand still to bandage wounds.")
	wound_treat_finish(H, user, affecting, used)

/datum/task/timed/medical_wound_treat
	complete_proc = /obj/item/stack/medical/proc/wound_treat_done
	cancel_proc = /obj/item/stack/medical/proc/wound_treat_interrupted
	var/mob/living/carbon/human/H
	var/list/wounds
	var/index
	var/used
	var/available

/obj/item/stack/medical/proc/wound_treat_done(datum/task/timed/medical_wound_treat/task)
	var/mob/living/carbon/human/H = task.H
	var/mob/living/user = task.actor
	var/obj/item/organ/external/affecting = task.target
	var/list/wounds = task.wounds
	var/index = task.index
	var/used = task.used
	var/available = task.available
	if(wound_already_treated(H, user, affecting))
		return
	if(used >= available)
		balloon_alert(user, "you run out of [src]!")
		wound_treat_finish(H, user, affecting, used)
		return
	used = apply_wound_treatment(wounds[index], H, user, affecting, used)
	wound_treat_step(H, user, affecting, wounds, index + 1, used, available)

/obj/item/stack/medical/proc/wound_treat_finish(mob/living/carbon/human/H, mob/living/user, obj/item/organ/external/affecting, used)
	if(!affecting)
		return
	affecting.update_damages()
	if(used == amount)
		if(affecting.is_bandaged())
			balloon_alert(user, "\the [src] is used up.")
		else
			balloon_alert(user, "\the [src] is used up, but there are more wounds to treat on \the [affecting.name].")
	use(used)

/obj/item/stack/medical/crude_pack/wound_treat_delay(datum/affliction/wound/W)
	return W.damage / 3

/obj/item/stack/medical/crude_pack/apply_wound_treatment(datum/affliction/wound/W, mob/living/carbon/human/H, mob/living/user, obj/item/organ/external/affecting, used)
	if (W.current_stage <= W.max_bleeding_stage)
		user.balloon_alert_visible("\the [user] bandages \a [W.desc] on [H]'s [affecting.name].", \
									"you bandage \a [W.desc] on [H]'s [affecting.name]." )
	else
		user.balloon_alert_visible("\the [user] places a bandage over \a [W.desc] on [H]'s [affecting.name].", \
									"you place a bandage over \a [W.desc] on [H]'s [affecting.name]." )
	return ..()

/obj/item/stack/medical/bruise_pack/apply_wound_treatment(datum/affliction/wound/W, mob/living/carbon/human/H, mob/living/user, obj/item/organ/external/affecting, used)
	if (W.current_stage <= W.max_bleeding_stage)
		user.balloon_alert_visible("\the [user] bandages \a [W.desc] on [H]'s [affecting.name].", \
									"bandaged \a [W.desc] on [H]'s [affecting.name]." )
	else if (W.damage_type == BRUISE)
		user.balloon_alert_visible("\the [user] places a bruise patch over \a [W.desc] on [H]'s [affecting.name].", \
									"placed bruise patch over \a [W.desc] on [H]'s [affecting.name]." )
	else
		user.balloon_alert_visible("\the [user] places a bandaid over \a [W.desc] on [H]'s [affecting.name].", \
									"placed bandaid over \a [W.desc] on [H]'s [affecting.name]." )
	return ..()

/obj/item/stack/medical/advanced/bruise_pack/wound_needs_treatment(datum/affliction/wound/W)
	return !W.internal && !(W.bandaged && W.disinfected)

/obj/item/stack/medical/advanced/bruise_pack/wound_already_treated(mob/living/carbon/human/H, mob/living/user, obj/item/organ/external/affecting)
	if(affecting.is_bandaged() && affecting.is_disinfected()) // We do a second check after the delay, in case it was bandaged after the first check.
		balloon_alert(user, "[H]'s [affecting.name] is already bandaged.")
		return TRUE
	return FALSE

/obj/item/stack/medical/advanced/bruise_pack/apply_wound_treatment(datum/affliction/wound/W, mob/living/carbon/human/H, mob/living/user, obj/item/organ/external/affecting, used)
	if (W.current_stage <= W.max_bleeding_stage)
		user.balloon_alert_visible("\the [user] cleans \a [W.desc] on [H]'s [affecting.name] and seals the edges with bioglue.", \
									"cleaning and sealing \a [W.desc] on [H]'s [affecting.name]." )
	else if (W.damage_type == BRUISE)
		user.balloon_alert_visible("\the [user] places a medical patch over \a [W.desc] on [H]'s [affecting.name].", \
									"placed medical patch over \a [W.desc] on [H]'s [affecting.name]." )
	else
		user.balloon_alert_visible("\the [user] smears some bioglue over \a [W.desc] on [H]'s [affecting.name].", \
									"smeared bioglue over \a [W.desc] on [H]'s [affecting.name]." )
	W.receive_tagged_treatment(TREAT_WOUND_PACKING, 1)
	W.disinfect()
	playsound(src, apply_sounds, 25)
	update_icon()
	// B9: one charge per wound treated; the tissue repair is applied once, in finish.
	return used + 1

/// The kit's tissue repair lands once for the whole pass, not once per wound.
/obj/item/stack/medical/advanced/bruise_pack/wound_treat_finish(mob/living/carbon/human/H, mob/living/user, obj/item/organ/external/affecting, used)
	if(used && affecting && H)
		H.mend(TREAT_TISSUE_REPAIR, heal_brute, affecting.organ_tag)
	return ..()

/obj/item/stack/medical/proc/upgrade_stack(upgrade_amount)
	. = FALSE

	var/turf/T = get_turf(src)

	if(ispath(upgrade_to) && use(upgrade_amount))
		var/obj/item/stack/medical/M = new upgrade_to(T, upgrade_amount)
		return M

	return .

/obj/item/stack/medical/crude_pack
	name = "crude bandage"
	singular_name = "crude bandage length"
	desc = "Some bandages to wrap around bloody stumps."
	icon_state = "gauze"
	no_variants = FALSE
	apply_sounds = SFX_EFFECTS_RIP_MIX

	upgrade_to = /obj/item/stack/medical/bruise_pack

/obj/item/stack/medical/crude_pack/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(..() == ITEM_INTERACT_FAILURE)
		return ITEM_INTERACT_FAILURE

	if (ishuman(M))
		var/mob/living/carbon/human/H = M
		var/obj/item/organ/external/affecting = H.get_organ(user.zone_sel.selecting)

		if(affecting.open)
			balloon_alert(user, "the [affecting.name] is cut open!")
			return

		if(affecting.is_bandaged())
			balloon_alert(user, "[M]'s [affecting.name] is already bandaged.")
			return ITEM_INTERACT_FAILURE
		else
			var/available = get_amount()
			user.balloon_alert_visible("\the [user] starts bandaging [M]'s [affecting.name].", \
											"bandaging [M]'s [affecting.name]." )
			wound_treat_step(H, user, affecting, affecting.get_wounds().Copy(), 1, 0, available)
			return ITEM_INTERACT_SUCCESS

/obj/item/stack/medical/bruise_pack
	name = "roll of gauze"
	singular_name = "gauze length"
	desc = "Some sterile gauze to wrap around bloody stumps."
	icon_state = "brutepack"
	no_variants = FALSE
	apply_sounds = SFX_EFFECTS_RIP_MIX
	drop_sound = SFX_ITEMS_DROP_GLOVES
	pickup_sound = SFX_ITEMS_PICKUP_GLOVES

	upgrade_to = /obj/item/stack/medical/advanced/bruise_pack

/obj/item/stack/medical/bruise_pack/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(..() == ITEM_INTERACT_FAILURE)
		return ITEM_INTERACT_FAILURE

	if (ishuman(M))
		var/mob/living/carbon/human/H = M
		var/obj/item/organ/external/affecting = H.get_organ(user.zone_sel.selecting)

		if(affecting.open)
			balloon_alert(user, "the [affecting.name] is cut open!")
			return

		if(affecting.is_bandaged())
			balloon_alert(user, "[M]'s [affecting.name] is already bandaged.")
			return ITEM_INTERACT_FAILURE
		else
			var/available = get_amount()
			user.balloon_alert_visible("\the [user] starts treating [M]'s [affecting.name].", \
										"treating [M]'s [affecting.name]." )
			wound_treat_step(H, user, affecting, affecting.get_wounds().Copy(), 1, 0, available)
			return ITEM_INTERACT_SUCCESS

/obj/item/stack/medical/ointment
	name = "ointment"
	desc = "Used to treat those nasty burns."
	gender = PLURAL
	singular_name = "ointment"
	icon_state = "ointment"
	heal_burn = 1
	no_variants = FALSE
	apply_sounds = SFX_EFFECTS_OINTMENT
	drop_sound = SFX_ITEMS_DROP_HERB
	pickup_sound = SFX_ITEMS_PICKUP_HERB

/obj/item/stack/medical/ointment/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(..() == ITEM_INTERACT_FAILURE)
		return ITEM_INTERACT_FAILURE

	if (ishuman(M))
		var/mob/living/carbon/human/H = M
		var/obj/item/organ/external/affecting = H.get_organ(user.zone_sel.selecting)

		if(affecting.open)
			user.balloon_alert(user, "the [affecting.name] is cut open!")
			return

		if(affecting.is_salved())
			user.balloon_alert(user, "the wounds on [M]'s [affecting.name] have already been salved.")
			return ITEM_INTERACT_FAILURE
		else
			user.balloon_alert_visible("\the [user] starts salving wounds on [M]'s [affecting.name].", \
										"salving the wounds on [M]'s [affecting.name]." )
			task_start(/datum/task/timed/ointment_attack, user, affecting, M = M)
			return ITEM_INTERACT_SUCCESS

/datum/task/timed/ointment_attack
	duration = 1 SECOND
	complete_proc = /obj/item/stack/medical/ointment/proc/attack_timed_done
	cancel_proc = /obj/item/stack/medical/ointment/proc/attack_timed_failed
	var/mob/living/M

/obj/item/stack/medical/ointment/proc/attack_timed_done(datum/task/timed/ointment_attack/task)
	var/mob/living/M = task.M
	var/mob/living/user = task.actor
	var/obj/item/organ/external/affecting = task.target
	if(affecting.is_salved()) // We do a second check after the delay, in case it was bandaged after the first check.
		user.balloon_alert(user, "[M]'s [affecting.name] have already been salved.")
		return ITEM_INTERACT_FAILURE
	user.balloon_alert_visible("[user] salved wounds on [M]'s [affecting.name].", \
								"salved wounds on [M]'s [affecting.name]." )
	use(1)
	affecting.salve()
	playsound(src, apply_sounds, 25)
	return ITEM_INTERACT_SUCCESS

/obj/item/stack/medical/ointment/proc/attack_timed_failed(datum/task/timed/ointment_attack/task)
	var/mob/living/user = task.actor
	user.balloon_alert(user, "stand still to salve wounds.")
	return ITEM_INTERACT_FAILURE

/obj/item/stack/medical/ointment/simple
	name = "ointment paste"
	desc = "A simple thick paste used to salve burns."
	singular_name = "old-ointment"
	icon_state = "old-ointment"

/obj/item/stack/medical/advanced/bruise_pack
	name = "advanced trauma kit"
	singular_name = "advanced trauma kit"
	desc = "An advanced trauma kit for severe injuries."
	icon_state = "traumakit"
	heal_brute = 7
	apply_sounds = SFX_EFFECTS_RIP_MIX_2

/obj/item/stack/medical/advanced/bruise_pack/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(..() == ITEM_INTERACT_FAILURE)
		return ITEM_INTERACT_FAILURE

	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		var/obj/item/organ/external/affecting = H.get_organ(user.zone_sel.selecting)

		if(affecting.open)
			balloon_alert(user, "the [affecting.name] is cut open!")
			return

		if(affecting.is_bandaged() && affecting.is_disinfected())
			balloon_alert(user, "[M]'s [affecting.name] have already been treated.")
			return 1
		else
			var/available = get_amount()
			user.balloon_alert_visible("\the [user] starts treating [M]'s [affecting.name].", \
										"treating [M]'s [affecting.name]." )
			wound_treat_step(H, user, affecting, affecting.get_wounds().Copy(), 1, 0, available)
			return ITEM_INTERACT_SUCCESS
	return ITEM_INTERACT_FAILURE

/obj/item/stack/medical/advanced/ointment
	name = "advanced burn kit"
	singular_name = "advanced burn kit"
	desc = "An advanced treatment kit for severe burns."
	icon_state = "burnkit"
	heal_burn = 7
	apply_sounds = SFX_EFFECTS_OINTMENT

/obj/item/stack/medical/advanced/ointment/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(..() == ITEM_INTERACT_FAILURE)
		return ITEM_INTERACT_FAILURE

	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		var/obj/item/organ/external/affecting = H.get_organ(user.zone_sel.selecting)

		if(affecting.open)
			user.balloon_alert(user, "the [affecting.name] is cut open!")
			return ITEM_INTERACT_FAILURE // B20: an open limb is surgery's, not a burn kit's

		if(affecting.is_salved())
			user.balloon_alert(user, "[M]'s [affecting.name] has already been salved.")
			return ITEM_INTERACT_FAILURE
		else
			user.balloon_alert_visible("\the [user] starts salving wounds on [M]'s [affecting.name].", \
										"salving the wounds on [M]'s [affecting.name]." )
			task_start(/datum/task/timed/ointment_attack2, user, affecting, M = M, H = H)
			return ITEM_INTERACT_SUCCESS
	return ITEM_INTERACT_FAILURE

/datum/task/timed/ointment_attack2
	duration = 1 SECOND
	complete_proc = /obj/item/stack/medical/advanced/ointment/proc/attack_timed_done2
	cancel_proc = /obj/item/stack/medical/advanced/ointment/proc/attack_timed_failed2
	var/mob/living/M
	var/mob/living/carbon/human/H

/obj/item/stack/medical/advanced/ointment/proc/attack_timed_done2(datum/task/timed/ointment_attack2/task)
	var/mob/living/M = task.M
	var/mob/living/user = task.actor
	var/mob/living/carbon/human/H = task.H
	var/obj/item/organ/external/affecting = task.target
	if(affecting.is_salved()) // We do a second check after the delay, in case it was bandaged after the first check.
		user.balloon_alert(user, "[M]'s [affecting.name] have already been salved.")
		return ITEM_INTERACT_FAILURE
	user.balloon_alert_visible("[user] covers wounds on [M]'s [affecting.name] with regenerative membrane.", \
							"covered wounds on [M]'s [affecting.name] with regenerative membrane." )
	H.mend(TREAT_BURN_CARE, heal_burn, affecting.organ_tag)
	use(1)
	affecting.salve()
	playsound(src, apply_sounds, 25)
	update_icon()
	return ITEM_INTERACT_SUCCESS

/obj/item/stack/medical/advanced/ointment/proc/attack_timed_failed2(datum/task/timed/ointment_attack2/task)
	var/mob/living/user = task.actor
	user.balloon_alert(user, "stand still to salve wounds.")
	return ITEM_INTERACT_FAILURE

/obj/item/stack/medical/splint
	name = "medical splints"
	singular_name = "medical splint"
	desc = "Modular splints capable of supporting and immobilizing bones in all areas of the body."
	icon_state = "splint"
	amount = 5
	max_amount = 5
	drop_sound = SFX_ITEMS_DROP_HAT
	pickup_sound = SFX_ITEMS_PICKUP_HAT

// List of organs you can splint, natch.
TYPE_TABLE_DECLARE(/obj/item/stack/medical/splint, splint_organs, list(BP_HEAD, BP_L_HAND, BP_R_HAND, BP_L_ARM, BP_R_ARM, BP_L_FOOT, BP_R_FOOT, BP_L_LEG, BP_R_LEG, BP_GROIN, BP_TORSO))


/obj/item/stack/medical/splint/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(..() == ITEM_INTERACT_FAILURE)
		return ITEM_INTERACT_FAILURE

	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		var/obj/item/organ/external/affecting = H.get_organ(user.zone_sel.selecting)
		var/limb = affecting.name
		if(!(affecting.organ_tag in TYPE_TABLE_GET(src, splint_organs)))
			balloon_alert(user, "you can't use \the [src] to apply a splint there!")
			return ITEM_INTERACT_FAILURE
		if(affecting.splinted)
			balloon_alert(user, "[M]'s [limb] is already splinted!")
			return ITEM_INTERACT_FAILURE
		if (M != user)
			user.balloon_alert_visible("[user] starts to apply \the [src] to [M]'s [limb].", "applying \the [src] to [M]'s [limb].", "You hear something being wrapped.")
		else
			if(( !user.hand && (affecting.organ_tag in list(BP_R_ARM, BP_R_HAND)) || \
				user.hand && (affecting.organ_tag in list(BP_L_ARM, BP_L_HAND)) ))
				balloon_alert(user, "you can't apply a splint to the arm you're using!")
				return ITEM_INTERACT_FAILURE
			user.balloon_alert_visible("[user] starts to apply \the [src] to their [limb].", "applying \the [src] to your [limb].", "You hear something being wrapped.")
		task_start(/datum/task/timed/splint_attack, user, affecting, M = M, limb = limb)
		return ITEM_INTERACT_FAILURE

/datum/task/timed/splint_attack
	duration = 5 SECONDS
	complete_proc = /obj/item/stack/medical/splint/proc/attack_timed_done3
	var/mob/living/M
	var/limb

/obj/item/stack/medical/splint/proc/attack_timed_done3(datum/task/timed/splint_attack/task)
	var/mob/living/M = task.M
	var/mob/living/user = task.actor
	var/obj/item/organ/external/affecting = task.target
	var/limb = task.limb
	if(affecting.splinted)
		balloon_alert(user, "[M]'s [limb] is already splinted!")
		return ITEM_INTERACT_FAILURE
	if(M == user && prob(75))
		user.balloon_alert_visible("\the [user] fumbles [src].", "fumbling [src].", "You hear something being wrapped.")
		return ITEM_INTERACT_FAILURE
	if(ishuman(user))
		var/obj/item/stack/medical/splint/S = split(1)
		if(S)
			if(affecting.apply_splint(S))
				S.forceMove(affecting)
				if (M != user)
					user.balloon_alert_visible("\the [user] finishes applying [src] to [M]'s [limb].", "finished applying \the [src] to [M]'s [limb].", "You hear something being wrapped.")
				else
					user.balloon_alert_visible("\the [user] successfully applies [src] to their [limb].", "successfully applied \the [src] to your [limb].", "You hear something being wrapped.")
				return ITEM_INTERACT_FAILURE
			S.dropInto(src.loc) //didn't get applied, so just drop it
	if(isrobot(user))
		var/obj/item/stack/medical/splint/B = src
		if(B)
			if(affecting.apply_splint(B))
				B.forceMove(affecting)
				user.balloon_alert_visible("\the [user] finishes applying [src] to [M]'s [limb].", "finish applying \the [src] to [M]'s [limb].", "You hear something being wrapped.")
				B.use(1)
				return ITEM_INTERACT_SUCCESS
	user.balloon_alert_visible("\the [user] fails to apply [src].", "failed to apply [src].", "You hear something being wrapped.")

/obj/item/stack/medical/splint/ghetto
	name = "makeshift splints"
	singular_name = "makeshift splint"
	desc = "For holding your limbs in place with duct tape and scrap metal."
	icon_state = "tape-splint"
	amount = 1

TYPE_TABLE(/obj/item/stack/medical/splint/ghetto, splint_organs, list(BP_L_ARM, BP_R_ARM, BP_L_LEG, BP_R_LEG))


/obj/item/stack/medical/advanced
	icon = 'icons/obj/stacks_vr.dmi'

/obj/item/stack/medical/advanced/Initialize(mapload)
	. = ..()
	update_icon()

/// The pack shows how many are left in steps.
/obj/item/stack/medical/advanced/look_state()
	switch(amount)
		if(1 to 2)
			return initial(icon_state)
		if(3 to 4)
			return "[initial(icon_state)]_4"
		if(5 to 6)
			return "[initial(icon_state)]_6"
		if(7 to 8)
			return "[initial(icon_state)]_8"
		if(9)
			return "[initial(icon_state)]_9"
	return "[initial(icon_state)]_10"


/obj/item/stack/medical/advanced/clotting
	name = "liquid bandage kit"
	singular_name = "liquid bandage kit"
	desc = "A spray that stops bleeding using a patented chemical cocktail. Non-refillable. Only one use required per patient."
	icon_state = "clotkit"
	heal_burn = 0
	heal_brute = 2 // Only applies to non-humans, to give this some slight application on animals
	apply_sounds = SFX_EFFECTS_SPRAY_MIX
	amount = 5
	max_amount = 5

/obj/item/stack/medical/advanced/clotting/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(..() == ITEM_INTERACT_FAILURE)
		return ITEM_INTERACT_FAILURE

	if(!ishuman(M))
		return ITEM_INTERACT_FAILURE
	var/mob/living/carbon/human/H = M

	var/clotted = 0
	var/too_far_gone = 0

	for(var/obj/item/organ/external/affecting as anything in H.organs) //'organs' is just external organs, as opposed to internal organs (organ_in / INTERNAL_ORGANS)

		// No amount of clotting is going to help you here.
		if(affecting.open)
			too_far_gone++
			continue

		for(var/datum/affliction/wound/W as anything in affecting.get_wounds())
			// No need
			if(W.bandaged)
				continue
			// It's not that amazing
			if(W.internal)
				continue
			if(W.current_stage <= W.max_bleeding_stage)
				clotted++
			W.receive_tagged_treatment(TREAT_WOUND_PACKING, 1)

	var/healmessage = span_notice("You spray [src] onto [H], sealing [clotted ? clotted : "no"] wounds.")
	if(too_far_gone)
		healmessage += " " + span_warning("You can see some wounds that are too large where the spray is not taking effect.")

	to_chat(user, healmessage)
	use(1)
	playsound(src, apply_sounds, 25)
	update_icon()
	return ITEM_INTERACT_SUCCESS

/// The kit shows its count.
/obj/item/stack/medical/advanced/clotting/look_state()
	return "[initial(icon_state)]_[amount]"
