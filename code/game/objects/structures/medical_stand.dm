/obj/structure/medical_stand
	name = "medical stand"
	icon = 'icons/obj/medical_stand.dmi'
	desc = "Medical stand used to hang reagents for transfusion and to hold anesthetic tank."
	icon_state = "medical_stand_empty"
	silicon_use = ROBOT_USE_HAND_ADJACENT

	//gas stuff
	var/obj/item/tank/tank
	var/obj/item/clothing/mask/breath/contained

	var/spawn_type = null
	var/mask_type = /obj/item/clothing/mask/breath/medical

	var/is_loosen = TRUE
	//blood stuff
	var/mode = 1 // 1 is injecting, 0 is taking blood.
	var/obj/item/reagent_containers/beaker
	var/static/list/transfer_amounts = list(REM, 1, 2)
	var/transfer_amount = 1

CAPABILITIES(/obj/structure/medical_stand)
	ref_one(nameof(attached))
	ref_one(nameof(breather))
	every(2 SECONDS, then(PROC_REF(medical_stand_step)), when = cond_any(nameof(valve_opened), nameof(breather), nameof(attached)))
	owns_one(nameof(contained), /obj/item/clothing/mask/breath, starts = nameof(mask_type))
	owns_one(nameof(beaker), /obj/item/reagent_containers)
	owns_one(nameof(tank), /obj/item/tank, starts = nameof(spawn_type))
	op("toggle_iv_mode", menu(), label("Toggle IV Mode"), needs(req(PROC_REF(actor_is_living), because = MSG(medical_stand/cannot))), then(PROC_REF(medical_stand_toggle_mode_effect)))
	op("set_iv_transfer", menu(), label("Set IV transfer amount"), then(PROC_REF(set_APTFT_effect)))
	op("medical_stand_interaction_hand", hand(), ungated(), then(PROC_REF(medical_stand_interaction_hand)))
	op("medical_stand_interaction_item", item(/obj/item), then(PROC_REF(medical_stand_interaction_item)))
	op("use_wrench", tool(TOOL_WRENCH), wait(0), then(PROC_REF(wrench_used)))
	// What a drag of a patient onto the stand (and the choice it asks) starts; the patient comes with the call.
	op("remove_mask", ai(), takes("patient"), wait(3 SECONDS), then(PROC_REF(mask_removed)))
	op("place_mask", ai(), takes("patient"), wait(10 SECONDS), then(PROC_REF(mask_placed)))
	op("remove_needle", ai(), takes("patient"), wait(2 SECONDS), then(PROC_REF(needle_removed)))
	op("insert_needle", ai(), takes("patient"), wait(5 SECONDS), on_interrupt(PROC_REF(needle_slipped)), then(PROC_REF(needle_inserted)))

MSG_DEF_SELF(medical_stand/cannot, "You can't do that.")

/// Only a living thing works the stand's menu.
/obj/structure/medical_stand/proc/actor_is_living(datum/act/op/A)
	return isliving(A.actor)

/obj/structure/medical_stand/var/mob/living/carbon/human/breather
/obj/structure/medical_stand/var/valve_opened = FALSE
TRACKED(/obj/structure/medical_stand, valve_opened)
/obj/structure/medical_stand/var/mob/living/carbon/attached

/// The tank and the beaker on the stand, drawn from what they are: a change of either (the beaker's level or colour) redraws the stand.
/obj/structure/medical_stand/draw(datum/look/look)
	..()
	look.watch(tank)
	look.watch(beaker)
	if(tank)
		look.overlay(breather() ? "tube_active" : "tube")
		look.overlay(tank_look_state(tank))
	if(beaker)
		look.overlay("beaker")
		look.overlay(attached() ? "line_active" : "line")
		var/datum/reagents/reagents = beaker.reagents
		if(reagents.total_volume)
			var/percent = round((reagents.total_volume / beaker.volume) * 100)
			look.overlay(look_overlay_image('icons/obj/medical_stand.dmi', fill_look_state(percent), color = reagents.get_color()))

/// The overlay state of the tank by what it holds.
/obj/structure/medical_stand/proc/tank_look_state(obj/item/tank/T)
	if(istype(T, /obj/item/tank/anesthetic))
		return "tank_anest"
	if(istype(T, /obj/item/tank/nitrogen))
		return "tank_nitro"
	if(istype(T, /obj/item/tank/oxygen))
		return "tank_oxyg"
	if(istype(T, /obj/item/tank/phoron))
		return "tank_plasma"
	return "tank_other"

/// The overlay state of the reagent bag by how full it is (under a tenth the bare "reagent").
/obj/structure/medical_stand/proc/fill_look_state(percent)
	switch(percent)
		if(10 to 24)
			return "reagent10"
		if(25 to 49)
			return "reagent25"
		if(50 to 74)
			return "reagent50"
		if(75 to 79)
			return "reagent75"
		if(80 to 90)
			return "reagent80"
		if(91 to INFINITY)
			return "reagent100"
	return "reagent"

// the breathing mask retracts from its patient.
/obj/structure/medical_stand/lifecycle_prerelease()
	..()
	if(breather())
		breather().internal = null
		breather().internals?.icon_state = "internal0"
		breather().remove_from_mob(contained)
		src.visible_message(span_notice("The mask rapidly retracts just before /the [src] is destroyed!"))

/obj/structure/medical_stand/MouseDrop(mob/living/carbon/human/target, src_location, over_location)
	..()
	if(istype(target))
		var/mob/user = usr
		if(!ismob(user) || user.stat == DEAD || !CanMouseDrop(target, user))
			return
		var/list/available_options = list()
		if (tank)
			available_options += "Gas mask"
		if (beaker)
			available_options += "Drip needle"

		if(available_options.len > 1)
			open_request(src, /datum/prompt/choice/medical_stand_attach, PROC_REF(attach_choice_made), answerer = user, title = "Attach/Detach Choice", question = "What do you want to attach/detach?", choices = available_options, patient = target, ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE, timeout = 0)
		else if(available_options.len)
			attach_action(user, available_options[1], target)

/// The choice of what to attach to or take off a patient: the patient is kept on the question.
/datum/prompt/choice/medical_stand_attach
	var/mob/living/carbon/human/patient

CAPABILITIES(/datum/prompt/choice/medical_stand_attach)
	ref_one(nameof(patient), /mob/living/carbon/human)

/obj/structure/medical_stand/proc/attach_choice_made(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/medical_stand_attach/R = A.request
	attach_action(R.answerer, A.answer.value, R.patient)

/obj/structure/medical_stand/proc/attach_action(mob/user, action_type, mob/living/carbon/human/target)
	if(!user || user.stat == DEAD || !CanMouseDrop(target, user))
		return
	switch (action_type)
		if("Gas mask")
			if(!can_apply_to_target(target, user)) // There is no point in attempting to apply a mask if it's impossible.
				return
			if (breather())
				src.add_fingerprint(user)
				perform_op(user, src, "remove_mask", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("patient" = target))
				return
			act_message(user, target, MSG_SELF(span_notice("You begin carefully placing the mask onto %T%.")), \
				MSG_OTHERS(span_infoplain(span_bold("%U%") + " begins carefully placing the mask onto %T%.")))
			perform_op(user, src, "place_mask", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("patient" = target))
			return
		if("Drip needle")
			if(attached())
				perform_op(user, src, "remove_needle", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("patient" = target))
			else if(ishuman(target))
				act_message(user, target, MSG_SELF(span_notice("You begin inserting needle into %T%'s vein.")), \
					MSG_OTHERS(span_infoplain(span_bold("%U%") + " begins inserting needle into %T%'s vein.")))
				perform_op(user, src, "insert_needle", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("patient" = target))

/obj/structure/medical_stand/proc/needle_removed(datum/act/op/A)
	if(!attached())
		return OP_OK
	visible_message("\The [attached()] is taken off \the [src]")
	rel_clear(src, nameof(attached))
	return OP_OK

/// The hand slipped: the user moved, or the patient did, before the needle was in.
/obj/structure/medical_stand/proc/needle_slipped(datum/act/op/A)
	var/mob/living/carbon/human/target = A.arg("patient")
	var/mob/user = A.actor
	if(!target || !user)
		return
	act_message(user, target, MSG_SELF(span_notice("Your hand slips and pricks %T%.")), MSG_OTHERS(span_notice("%U%'s hand slips and pricks %T%.")))
	target.injure(INJURY_PIERCE, 3, pick(BP_R_ARM, BP_L_ARM), src)

/obj/structure/medical_stand/proc/needle_inserted(datum/act/op/A)
	var/mob/living/carbon/human/target = A.arg("patient")
	var/mob/user = A.actor
	if(QDELETED(target) || !Adjacent(target))
		needle_slipped(A)
		return OP_OK
	if(attached())
		return OP_OK
	act_message(user, target, MSG_SELF(span_notice("You hook %T% up to \the [src].")), \
		MSG_OTHERS(span_infoplain(span_bold("%U%") + "hooks %T% up to \the [src].")))
	rel_set(src, nameof(attached), target)
	return OP_OK

/obj/structure/medical_stand/proc/mask_removed(datum/act/op/A)
	var/mob/living/carbon/human/target = A.arg("patient")
	if(!can_apply_to_target(target, A.actor))
		return OP_OK
	if(tank)
		tank.forceMove(src)
	if (breather().get_equipped_item(SLOT_ID_MASK) == contained)
		breather().remove_from_mob(contained)
		contained.forceMove(src)
	else
		rel_clear(src, nameof(contained))
		rel_set(src, nameof(contained), new mask_type(src))
	rel_clear(src, nameof(breather))
	src.visible_message(span_infoplain(span_bold("\The [contained]") + " slips to \the [src]!"))
	return OP_OK

/obj/structure/medical_stand/proc/mask_placed(datum/act/op/A)
	var/mob/living/carbon/human/target = A.arg("patient")
	var/mob/user = A.actor
	if(!can_apply_to_target(target, user))
		return OP_OK
	// place mask and add fingerprints
	act_message(user, target, MSG_SELF(span_notice("You have placed \the mask on %T%'s mouth.")), \
		MSG_OTHERS(span_notice("%U% has placed \the mask on %T%'s mouth.")))
	if(attach_mask(target))
		src.add_fingerprint(user)
	return OP_OK

/// Old attack_hand (it never reached the structure gate).
/obj/structure/medical_stand/proc/medical_stand_interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	var/list/available_options = list()
	if (tank)
		available_options += "Toggle valve"
		available_options += "Remove tank"
	if (beaker)
		available_options += "Remove vessel"

	if(available_options.len > 1)
		open_request(src, /datum/prompt/choice, PROC_REF(stand_action_chosen), answerer = user, title = "Stand Choice", question = "What do you want to do?", choices = available_options, ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE, timeout = 0)
		return TRUE
	if(available_options.len)
		stand_action(user, available_options[1])
	return TRUE

/obj/structure/medical_stand/proc/stand_action_chosen(datum/act/request/A)
	if(!A.answer)
		return
	stand_action(A.request.answerer, A.answer.value)

/obj/structure/medical_stand/proc/stand_action(mob/user, action_type)
	switch (action_type)
		if ("Remove tank")
			if (!tank)
				to_chat(user, span_warning("There is no tank in \the [src]!"))
				return
			else if (tank && is_loosen)
				act_message(user, src, MSG_SELF(span_warning("You remove \the [tank] from %T%.")), \
					MSG_OTHERS(span_warningplain(span_bold("%U%") + " removes \the [tank] from %T%.")))
				user.put_in_hands(tank)
				rel_take(src, nameof(tank))
				set_valve_opened(FALSE)
				return
			else if (!is_loosen)
				act_message(user, src, MSG_SELF(span_warning("You try to remove \the [tank] from %T% but it won't budge.")), \
					MSG_OTHERS(span_warningplain(span_bold("%U%") + " tries to removes \the [tank] from %T% but it won't budge.")))
				return
		if ("Toggle valve")
			if (!tank)
				to_chat(user, span_warning("There is no tank in \the [src]!"))
				return
			else
				if (valve_opened)
					act_message(user, src, others = span_infoplain(span_bold("%U%") + " closes valve on %T%!"), blind = span_notice("You close valve on %T%."))
					if(breather())
						breather().internals?.icon_state = "internal0"
						breather().internal = null
					set_valve_opened(FALSE)
				else
					act_message(user, src, others = span_infoplain(span_bold("%U%") + " opens valve on %T%!"), blind = span_notice("You open valve on %T%."))
					if(breather())
						breather().internal = tank
						breather().internals?.icon_state = "internal1"
					set_valve_opened(TRUE)
		if ("Remove vessel")
			if(beaker)
				beaker.forceMove(loc)
				rel_take(src, nameof(beaker))

/obj/structure/medical_stand/proc/medical_stand_toggle_mode_effect(datum/act/op/A)
	var/mob/user = A.actor
	if(user.incapacitated())
		return OP_OK

	mode = !mode
	to_chat(user, "The IV drip is now [mode ? "injecting" : "taking blood"].")
	return OP_OK

/obj/structure/medical_stand/proc/set_APTFT_effect(datum/act/op/A)
	open_request(src, /datum/prompt/choice, PROC_REF(transfer_amount_chosen), answerer = A.actor, title = "[src]", question = "Amount per transfer from this:", choices = transfer_amounts, ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE, timeout = 0)
	return OP_OK

/obj/structure/medical_stand/proc/transfer_amount_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/N = A.answer.value
	if(N)
		transfer_amount = N

/obj/structure/medical_stand/proc/attach_mask(mob/living/carbon/C)
	if(C && istype(C))
		if(C.equip_to_slot_if_possible(contained, SLOT_ID_MASK))
			if(tank)
				tank.forceMove(C)
			rel_set(src, nameof(breather), C)
			return TRUE

/obj/structure/medical_stand/proc/can_apply_to_target(mob/living/carbon/human/target, mob/user)
	if(!user)
		user = target
	// Check target validity
	if(!istype(target))
		to_chat(user, span_warning("\The [target] not compatible with machine."))
		return
	if(!target.organs_by_name[BP_HEAD])
		to_chat(user, span_warning("\The [target] doesn't have a head."))
		return
	if(!target.check_has_mouth())
		to_chat(user, span_warning("\The [target] doesn't have a mouth."))
		return
	if(target.get_equipped_item(SLOT_ID_MASK) && target != breather())
		to_chat(user, span_warning("\The [target] is already wearing a mask."))
		return
	if(target.get_equipped_item(SLOT_ID_HEAD) && (target.get_equipped_item(SLOT_ID_HEAD).body_parts_covered & FACE))
		to_chat(user, span_warning("Remove their [target.get_equipped_item(SLOT_ID_HEAD)] first."))
		return
	if(!tank)
		to_chat(user, span_warning("There is no tank in \the [src]."))
		return
	if(is_loosen)
		to_chat(user, span_warning("Tighten the nut with a wrench first."))
		return
	if(!Adjacent(target))
		return
	//when there is a breather:
	if(breather() && target != breather())
		to_chat(user, span_warning("\The [src] is already in use."))
		return
	//Checking if breather is still valid
	if(target == breather() && target.get_equipped_item(SLOT_ID_MASK) != contained)
		to_chat(user, span_warning("\The [target] is not using the supplied mask."))
		return
	return 1

/// Old attackby.
/obj/structure/medical_stand/proc/medical_stand_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(istype(W, /obj/item/tank))
		if(tank)
			to_chat(user, span_warning("\The [src] already has a tank installed!"))
		else if(!is_loosen)
			to_chat(user, span_warning("Loosen the nut with a wrench first."))
		else
			if(!move_into(src, nameof(src.tank), W, user))
				return TRUE
			act_message(user, src, MSG_SELF(span_notice("You attach %I% to %T%.")), MSG_OTHERS(span_bold("%U%") + " attaches %I% to %T%."), item = tank)
			src.add_fingerprint(user)
		return TRUE

	if (istype(W, /obj/item/reagent_containers))
		if(!isnull(src.beaker))
			to_chat(user, "There is already a reagent container loaded!")
			return TRUE
		if(!move_into(src, nameof(src.beaker), W, user))
			return TRUE
		to_chat(user, "You attach \the [W] to \the [src].")
		return TRUE
	return OP_DECLINE

/obj/structure/medical_stand/proc/wrench_used(datum/act/op/A)
	var/mob/user = A.actor
	if(valve_opened)
		to_chat(user, span_warning("Close the valve first."))
		return OP_OK
	if(!tank)
		to_chat(user, span_warning("There is no tank in \the [src]."))
		return OP_OK
	is_loosen = !is_loosen
	act_message(user, null, MSG_SELF(span_notice("You [is_loosen ? "loosen" : "tighten"] the nut holding [tank] in place.")), \
		MSG_OTHERS(span_notice("%U% [is_loosen ? "loosens" : "tightens"] the nut holding [tank] in place.")))
	return OP_OK

/obj/structure/medical_stand/examine(mob/user)
	. = ..()

	if (get_dist(src, user) > 2)
		return

	if(beaker)
		. += "The IV drip is [mode ? "injecting" : "taking blood"]."
		. += "It is set to transfer [transfer_amount]u of chemicals per cycle."
		if(beaker.reagents && beaker.reagents.total_volume)
			. += span_notice("Attached is \a [beaker] with [beaker.reagents.total_volume] units of liquid.")
		else
			. += span_notice("Attached is an empty [beaker].")
		. += span_notice("[attached() ? attached() : "No one"] is hooked up to it.")
	else
		. += span_notice("There is no vessel.")

	if(tank)
		if (!is_loosen)
			. += "\The [tank] connected."
		. += "The meter shows [round(tank.air_contents.return_pressure())]. The valve is [valve_opened == TRUE ? "open" : "closed"]."
		if (tank.distribute_pressure == 0)
			. += "Use wrench to replace tank."
	else
		. += span_notice("There is no tank.")

/obj/structure/medical_stand/proc/medical_stand_step(datum/act/timer/A)
	//Gas Stuff
	if(breather())
		if(!can_apply_to_target(breather()))
			if(tank)
				tank.forceMove(src)
			if (breather().get_equipped_item(SLOT_ID_MASK) == contained)
				breather().remove_from_mob(contained)
				contained.forceMove(src)
			else
				rel_clear(src, nameof(contained))
				rel_set(src, nameof(contained), new mask_type (src))
			src.visible_message(span_bold("\The [contained]") + " slips to \the [src]!")
			rel_clear(src, nameof(breather))
			return
		if(valve_opened)
			if (tank)
				breather().internal = tank
				breather().internals?.icon_state = "internal1"
		else
			breather().internals?.icon_state = "internal0"
			breather().internal = null
	else if (valve_opened)
		var/datum/gas_mixture/removed = tank.remove_air(0.01)
		var/datum/gas_mixture/environment = loc.return_air()
		environment.merge(removed)

	//Reagent Stuff
	if(attached())
		if(!Adjacent(attached()))
			visible_message("The needle is ripped out of [src.attached()], doesn't that hurt?")
			attached().injure(INJURY_PIERCE, 3, pick(BP_R_ARM, BP_L_ARM), src)
			rel_clear(src, nameof(attached))

	if(beaker)
		if(mode) // Give blood
			if(beaker.volume > 0)
				beaker.reagents.trans_to_mob(attached(), transfer_amount, CHEM_BLOOD)
		else // Take blood
			var/amount = beaker.reagents.maximum_volume - beaker.reagents.total_volume
			amount = min(amount, 4)

			if(amount == 0) // If the beaker is full, ping
				if(prob(5)) visible_message("\The [src] pings.")
				return

			var/mob/living/carbon/human/H = attached()
			if(!istype(H))
				return
			if(!H.dna)
				return
			if(H.has_mutation(NOCLONE))
				return
			if(H.species.flags & NO_BLOOD)
				return
			if(!H.should_have_organ(O_HEART))
				return

			// If the human is losing too much blood, beep.
			if(H.vessel.get_reagent_amount(REAGENT_ID_BLOOD) < H.species.blood_volume*H.species.blood_level_safe)
				visible_message("\The [src] beeps loudly.")

			var/datum/reagent/B = H.take_blood(beaker,amount)
			if (B)
				beaker.reagents.adopt_reagent(B)
				beaker.reagents.update_total()
				beaker.on_reagent_change()
				beaker.reagents.handle_reactions()


/obj/structure/medical_stand/anesthetic
	spawn_type = /obj/item/tank/anesthetic
	mask_type = /obj/item/clothing/mask/breath/medical
	is_loosen = FALSE

/// Relation view: breather (reads null once it is gone).
/obj/structure/medical_stand/proc/breather() as /mob/living/carbon/human
	return breather

/// Relation view: attached (reads null once it is gone).
/obj/structure/medical_stand/proc/attached() as /mob/living/carbon
	return attached


