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

/// Whether the limb has nothing left for this stack to do (someone else may finish the job during the wait).
/obj/item/stack/medical/proc/wound_fully_treated(obj/item/organ/external/affecting)
	return affecting.is_bandaged()

/// Treats W; returns the new count of stack units used.
/obj/item/stack/medical/proc/apply_wound_treatment(datum/affliction/wound/W, mob/living/carbon/human/H, mob/living/user, obj/item/organ/external/affecting, used)
	W.receive_tagged_treatment(TREAT_WOUND_PACKING, 1)
	playsound(src, apply_sounds, 25)
	return used + 1

/// One wound is treated per lap of a repeating wait, in the order the limb listed them when the work began; the cursor says where the next lap looks.
CAPABILITIES(/obj/item/stack/medical)
	op("treat_wounds", ai(), takes("patient", "limb", "wounds", "cursor"), needs(req(PROC_REF(wound_work_left), silent = TRUE)),
		wait(PROC_REF(wound_lap_time), keeps = HELD | TARGET_PRESENT | ALIVE | STAY, repeats = PROC_REF(wound_more), after_step = PROC_REF(wound_lap_done)),
		on_interrupt(PROC_REF(wound_interrupted)), then(PROC_REF(wound_finished)))

/// The index of the first wound at or after `start` that this stack still has work on, or 0.
/obj/item/stack/medical/proc/wound_find(list/wounds, start)
	for(var/index in start to length(wounds))
		var/datum/affliction/wound/candidate = wounds[index]
		if(!QDELETED(candidate) && wound_needs_treatment(candidate))
			return index
	return 0

/obj/item/stack/medical/proc/wound_next_index(datum/act/op/A)
	var/list/cursor = A.arg("cursor")
	return wound_find(A.arg("wounds"), cursor[1])

/// Starts treating the limb: the wait is the stack's op, a lap per wound (nothing to treat ends at once).
/obj/item/stack/medical/proc/wound_treat_start(mob/living/carbon/human/H, mob/living/user, obj/item/organ/external/affecting)
	var/list/wounds = affecting.get_wounds().Copy()
	if(!wound_find(wounds, 1))
		wound_treat_finish(H, user, affecting, 0)
		return
	perform_op(user, src, "treat_wounds", src, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("patient" = H, "limb" = affecting, "wounds" = wounds, "cursor" = list(1)))

/obj/item/stack/medical/proc/wound_work_left(datum/act/op/A)
	var/obj/item/organ/external/affecting = A.arg("limb")
	return !QDELETED(affecting) && !read_once(wound_fully_treated(affecting))

/// A lap takes as long as the wound is bad.
/obj/item/stack/medical/proc/wound_lap_time(datum/act/op/A)
	var/index = wound_next_index(A)
	if(!index)
		return 1 TICK
	var/list/wounds = A.arg("wounds")
	return max(1 TICK, wound_treat_delay(wounds[index]))

/// Another lap follows while a wound is left and the stack has a unit for it.
/obj/item/stack/medical/proc/wound_more(datum/act/op/A)
	if(wound_limited_by_amount() && A.laps() >= amount)
		return FALSE
	return wound_next_index(A) > 0

/// One wound treated.
/obj/item/stack/medical/proc/wound_lap_done(datum/act/op/A)
	var/mob/living/carbon/human/H = A.arg("patient")
	var/obj/item/organ/external/affecting = A.arg("limb")
	var/list/wounds = A.arg("wounds")
	var/list/cursor = A.arg("cursor")
	var/index = wound_next_index(A)
	if(!index || QDELETED(H) || QDELETED(affecting))
		return
	apply_wound_treatment(wounds[index], H, A.actor, affecting, A.laps() - 1)
	cursor[1] = index + 1

/obj/item/stack/medical/proc/wound_interrupted(datum/act/op/A)
	var/mob/living/carbon/human/H = A.arg("patient")
	var/obj/item/organ/external/affecting = A.arg("limb")
	if(!QDELETED(affecting) && wound_fully_treated(affecting))
		balloon_alert(A.actor, "[H]'s [affecting.name] is already bandaged.") // someone else finished the job during the wait
	else
		balloon_alert(A.actor, "stand still to bandage wounds.")
	wound_treat_finish(H, A.actor, affecting, A.laps())

/obj/item/stack/medical/proc/wound_finished(datum/act/op/A)
	wound_treat_finish(A.arg("patient"), A.actor, A.arg("limb"), A.laps())
	return OP_OK

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

/obj/item/stack/medical/advanced/bruise_pack/wound_fully_treated(obj/item/organ/external/affecting)
	return affecting.is_bandaged() && affecting.is_disinfected()

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
			user.balloon_alert_visible("\the [user] starts bandaging [M]'s [affecting.name].", \
											"bandaging [M]'s [affecting.name]." )
			wound_treat_start(H, user, affecting)
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
			user.balloon_alert_visible("\the [user] starts treating [M]'s [affecting.name].", \
										"treating [M]'s [affecting.name]." )
			wound_treat_start(H, user, affecting)
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
			perform_op(user, src, "salve", src, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("patient" = M, "limb" = affecting))
			return ITEM_INTERACT_SUCCESS

CAPABILITIES(/obj/item/stack/medical/ointment)
	op("salve", ai(), takes("patient", "limb"), wait(1 SECOND, keeps = HELD | TARGET_PRESENT | ALIVE | STAY), on_interrupt(PROC_REF(salve_failed)), then(PROC_REF(salve_done)))

/obj/item/stack/medical/ointment/proc/salve_done(datum/act/op/A)
	var/mob/living/M = A.arg("patient")
	var/mob/living/user = A.actor
	var/obj/item/organ/external/affecting = A.arg("limb")
	if(QDELETED(affecting))
		return OP_FAILED
	if(affecting.is_salved()) // We do a second check after the delay, in case it was bandaged after the first check.
		user.balloon_alert(user, "[M]'s [affecting.name] have already been salved.")
		return OP_FAILED
	user.balloon_alert_visible("[user] salved wounds on [M]'s [affecting.name].", \
								"salved wounds on [M]'s [affecting.name]." )
	use(1)
	affecting.salve()
	playsound(src, apply_sounds, 25)
	return OP_OK

/obj/item/stack/medical/ointment/proc/salve_failed(datum/act/op/A)
	A.actor.balloon_alert(A.actor, "stand still to salve wounds.")

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
			user.balloon_alert_visible("\the [user] starts treating [M]'s [affecting.name].", \
										"treating [M]'s [affecting.name]." )
			wound_treat_start(H, user, affecting)
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
			perform_op(user, src, "salve", src, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("patient" = H, "limb" = affecting))
			return ITEM_INTERACT_SUCCESS
	return ITEM_INTERACT_FAILURE

CAPABILITIES(/obj/item/stack/medical/advanced/ointment)
	op("salve", ai(), takes("patient", "limb"), wait(1 SECOND, keeps = HELD | TARGET_PRESENT | ALIVE | STAY), on_interrupt(PROC_REF(salve_failed)), then(PROC_REF(salve_done)))

/obj/item/stack/medical/advanced/ointment/proc/salve_done(datum/act/op/A)
	var/mob/living/carbon/human/H = A.arg("patient")
	var/mob/living/M = H
	var/mob/living/user = A.actor
	var/obj/item/organ/external/affecting = A.arg("limb")
	if(QDELETED(H) || QDELETED(affecting))
		return OP_FAILED
	if(affecting.is_salved()) // We do a second check after the delay, in case it was bandaged after the first check.
		user.balloon_alert(user, "[M]'s [affecting.name] have already been salved.")
		return OP_FAILED
	user.balloon_alert_visible("[user] covers wounds on [M]'s [affecting.name] with regenerative membrane.", \
							"covered wounds on [M]'s [affecting.name] with regenerative membrane." )
	H.mend(TREAT_BURN_CARE, heal_burn, affecting.organ_tag)
	use(1)
	affecting.salve()
	playsound(src, apply_sounds, 25)
	return OP_OK

/obj/item/stack/medical/advanced/ointment/proc/salve_failed(datum/act/op/A)
	A.actor.balloon_alert(A.actor, "stand still to salve wounds.")

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
		perform_op(user, src, "splint", src, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("patient" = M, "limb" = affecting))
		return ITEM_INTERACT_FAILURE

CAPABILITIES(/obj/item/stack/medical/splint)
	op("splint", ai(), takes("patient", "limb"), wait(5 SECONDS, keeps = HELD | TARGET_PRESENT | ALIVE | STAY), then(PROC_REF(splint_done)))

/obj/item/stack/medical/splint/proc/splint_done(datum/act/op/A)
	var/mob/living/M = A.arg("patient")
	var/mob/living/user = A.actor
	var/obj/item/organ/external/affecting = A.arg("limb")
	if(QDELETED(M) || QDELETED(affecting))
		return OP_FAILED
	var/limb = affecting.name
	if(affecting.splinted)
		balloon_alert(user, "[M]'s [limb] is already splinted!")
		return OP_FAILED
	if(M == user && prob(75))
		user.balloon_alert_visible("\the [user] fumbles [src].", "fumbling [src].", "You hear something being wrapped.")
		return OP_FAILED
	if(ishuman(user))
		var/obj/item/stack/medical/splint/S = split(1)
		if(S)
			if(affecting.apply_splint(S))
				S.forceMove(affecting)
				if (M != user)
					user.balloon_alert_visible("\the [user] finishes applying [src] to [M]'s [limb].", "finished applying \the [src] to [M]'s [limb].", "You hear something being wrapped.")
				else
					user.balloon_alert_visible("\the [user] successfully applies [src] to their [limb].", "successfully applied \the [src] to your [limb].", "You hear something being wrapped.")
				return OP_OK
			S.dropInto(src.loc) //didn't get applied, so just drop it
	if(isrobot(user))
		var/obj/item/stack/medical/splint/B = src
		if(B)
			if(affecting.apply_splint(B))
				B.forceMove(affecting)
				user.balloon_alert_visible("\the [user] finishes applying [src] to [M]'s [limb].", "finish applying \the [src] to [M]'s [limb].", "You hear something being wrapped.")
				B.use(1)
				return OP_OK
	user.balloon_alert_visible("\the [user] fails to apply [src].", "failed to apply [src].", "You hear something being wrapped.")
	return OP_FAILED

/obj/item/stack/medical/splint/ghetto
	name = "makeshift splints"
	singular_name = "makeshift splint"
	desc = "For holding your limbs in place with duct tape and scrap metal."
	icon_state = "tape-splint"
	amount = 1

TYPE_TABLE(/obj/item/stack/medical/splint/ghetto, splint_organs, list(BP_L_ARM, BP_R_ARM, BP_L_LEG, BP_R_LEG))


/obj/item/stack/medical/advanced
	icon = 'icons/obj/stacks_vr.dmi'

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
	return ITEM_INTERACT_SUCCESS

/// The kit shows its count.
/obj/item/stack/medical/advanced/clotting/look_state()
	return "[initial(icon_state)]_[amount]"
