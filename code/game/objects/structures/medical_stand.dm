/obj/structure/medical_stand
	name = "medical stand"
	icon = 'icons/obj/medical_stand.dmi'
	desc = "Medical stand used to hang reagents for transfusion and to hold anesthetic tank."
	icon_state = "medical_stand_empty"
	silicon_use = ROBOT_USE_HAND_ADJACENT

	//gas stuff
	var/obj/item/tank/tank
	var/breather_handle
	var/obj/item/clothing/mask/breath/contained

	var/spawn_type = null
	var/mask_type = /obj/item/clothing/mask/breath/medical

	var/is_loosen = TRUE
	var/valve_opened = FALSE
	//blood stuff
	var/attached_handle
	var/mode = 1 // 1 is injecting, 0 is taking blood.
	var/obj/item/reagent_containers/beaker
	var/static/list/transfer_amounts = list(REM, 1, 2)
	var/transfer_amount = 1

/obj/structure/medical_stand/Initialize(mapload)
	. = ..()
	update_icon()

/obj/structure/medical_stand/update_icon()
	cut_overlays()

	if (tank)
		if (breather())
			add_overlay("tube_active")
		else
			add_overlay("tube")
		if(istype(tank,/obj/item/tank/anesthetic))
			add_overlay("tank_anest")
		else if(istype(tank,/obj/item/tank/nitrogen))
			add_overlay("tank_nitro")
		else if(istype(tank,/obj/item/tank/oxygen))
			add_overlay("tank_oxyg")
		else if(istype(tank,/obj/item/tank/phoron))
			add_overlay("tank_plasma")
		else
			add_overlay("tank_other")

	if(beaker)
		add_overlay("beaker")
		if(attached())
			add_overlay("line_active")
		else
			add_overlay("line")
		var/datum/reagents/reagents = beaker.reagents
		var/percent = round((reagents.total_volume / beaker.volume) * 100)
		if(reagents.total_volume)
			var/image/filling = image('icons/obj/medical_stand.dmi', src, "reagent")

			switch(percent)
				if(10 to 24) 	filling.icon_state = "reagent10"
				if(25 to 49)	filling.icon_state = "reagent25"
				if(50 to 74)	filling.icon_state = "reagent50"
				if(75 to 79)	filling.icon_state = "reagent75"
				if(80 to 90)	filling.icon_state = "reagent80"
				if(91 to INFINITY)	filling.icon_state = "reagent100"
			if (filling.icon)
				filling.icon += reagents.get_color()
				add_overlay(filling)

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
		if(!ismob(user) || user.stat == DEAD || !CanMouseDrop(target))
			return
		var/list/available_options = list()
		if (tank)
			available_options += "Gas mask"
		if (beaker)
			available_options += "Drip needle"

		if(available_options.len > 1)
			om_ask(user, /datum/om/prompt/choice/medical_stand_attach, PROC_REF(attach_choice_made), choices = available_options, patient = target)
		else if(available_options.len)
			attach_action(user, available_options[1], target)

/datum/om/prompt/choice/medical_stand_attach
	title = "Attach/Detach Choice"
	message = "What do you want to attach/detach?"
	ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE
	var/mob/living/carbon/human/patient

/datum/om/prompt/choice/medical_stand_transfer
	message = "Amount per transfer from this:"
	ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE

/datum/om/prompt/choice/medical_stand_transfer/prepare()
	title = "[subject]"
	return TRUE

/obj/structure/medical_stand/proc/attach_choice_made(datum/om/prompt/choice/medical_stand_attach/ask)
	attach_action(ask.answerer, ask.choice, ask.patient)

/obj/structure/medical_stand/proc/attach_action(mob/user, action_type, mob/living/carbon/human/target)
	if(user.stat == DEAD || !CanMouseDrop(target))
		return
	switch (action_type)
		if("Gas mask")
			if(!can_apply_to_target(target, user)) // There is no point in attempting to apply a mask if it's impossible.
				return
			if (breather())
				src.add_fingerprint(user)
				om_task_timed(user, 3 SECONDS, target = target, receiver = src, on_done = PROC_REF(MouseDrop_timed_done), done_args = list(target, user))
				return
			user.visible_message(span_infoplain(span_bold("\The [user]") + " begins carefully placing the mask onto [target]."),
						span_notice("You begin carefully placing the mask onto [target]."))
			om_task_timed(user, 10 SECONDS, target = target, receiver = src, on_done = PROC_REF(MouseDrop_timed_done2), done_args = list(target, user))
			return
		if("Drip needle")
			if(attached())
				om_task_timed(user, 2 SECONDS, target = target, receiver = src, on_done = PROC_REF(needle_removed))
			else if(ishuman(target))
				user.visible_message(span_infoplain(span_bold("\The [user]") + " begins inserting needle into [target]'s vein."),
								span_notice("You begin inserting needle into [target]'s vein."))
				om_task_start(/datum/om/task/timed/medical_stand_needle_inserted, user, target, receiver = src)
			update_icon()

/obj/structure/medical_stand/proc/needle_removed()
	if(!attached())
		return
	visible_message("\The [attached()] is taken off \the [src]")
	attached_handle = null
	update_icon()

/obj/structure/medical_stand/proc/needle_slipped(datum/om/task/timed/medical_stand_needle_inserted/task)
	var/mob/living/carbon/human/target = task.target
	var/mob/user = task.actor
	if(!target || !user)
		return
	user.visible_message(span_notice("\The [user]'s hand slips and pricks \the [target]."),
				span_notice("Your hand slips and pricks \the [target]."))
	target.injure(INJURY_PIERCE, 3, pick(BP_R_ARM, BP_L_ARM), src)

/datum/om/task/timed/medical_stand_needle_inserted
	duration = 5 SECONDS
	complete_proc = /obj/structure/medical_stand/proc/needle_inserted
	cancel_proc = /obj/structure/medical_stand/proc/needle_slipped

/obj/structure/medical_stand/proc/needle_inserted(datum/om/task/timed/medical_stand_needle_inserted/task)
	var/mob/living/carbon/human/target = task.target
	var/mob/user = task.actor
	if(attached())
		return
	user.visible_message(span_infoplain(span_bold("\The [user]") + "hooks \the [target] up to \the [src]."),
					span_notice("You hook \the [target] up to \the [src]."))
	attached_handle = om_handle(target)
	om_task_periodic(src, PERIODIC_SLOW)
	update_icon()

/obj/structure/medical_stand/proc/MouseDrop_timed_done(mob/living/carbon/human/target, mob/user)
	if(!can_apply_to_target(target, user))
		return
	if(tank)
		tank.forceMove(src)
	if (breather().get_equipped_item(SLOT_ID_MASK) == contained)
		breather().remove_from_mob(contained)
		contained.forceMove(src)
	else
		qdel(contained)
		contained = new mask_type(src)
	breather_handle = null
	src.visible_message(span_infoplain(span_bold("\The [contained]") + " slips to \the [src]!"))
	update_icon()
	return
/obj/structure/medical_stand/proc/MouseDrop_timed_done2(mob/living/carbon/human/target, mob/user)
	if(!can_apply_to_target(target, user))
		return
	// place mask and add fingerprints
	user.visible_message(span_notice("\The [user] has placed \the mask on [target]'s mouth."),
						span_notice("You have placed \the mask on [target]'s mouth."))
	if(attach_mask(target))
		src.add_fingerprint(user)
		update_icon()
		om_task_periodic(src, PERIODIC_SLOW)
	return

DECLARE_INTERACTIONS(/obj/structure/medical_stand, \
	INTERACT_HAND_UNGATED(null, PROC_REF(medical_stand_interaction_hand)), \
	INTERACT_ITEM(null, PROC_REF(medical_stand_interaction_item)), \
)

/// Old attack_hand (it never reached the structure gate).
/obj/structure/medical_stand/proc/medical_stand_interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	var/list/available_options = list()
	if (tank)
		available_options += "Toggle valve"
		available_options += "Remove tank"
	if (beaker)
		available_options += "Remove vessel"

	if(available_options.len > 1)
		om_ask(user, /datum/om/prompt/choice, PROC_REF(stand_action_chosen), choices = available_options, title = "Stand Choice", message = "What do you want to do?", ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE)
		return TRUE
	if(available_options.len)
		stand_action(user, available_options[1])
	return TRUE

/obj/structure/medical_stand/proc/stand_action_chosen(datum/om/prompt/choice/ask)
	stand_action(ask.answerer, ask.choice)

/obj/structure/medical_stand/proc/stand_action(mob/user, action_type)
	switch (action_type)
		if ("Remove tank")
			if (!tank)
				to_chat(user, span_warning("There is no tank in \the [src]!"))
				return
			else if (tank && is_loosen)
				user.visible_message(span_warningplain(span_bold("\The [user]") + " removes \the [tank] from \the [src]."), span_warning("You remove \the [tank] from \the [src]."))
				user.put_in_hands(tank)
				tank = null
				valve_opened = FALSE
				om_task_periodic_stop(src)
				update_icon()
				return
			else if (!is_loosen)
				user.visible_message(span_warningplain(span_bold("\The [user]") + " tries to removes \the [tank] from \the [src] but it won't budge."), span_warning("You try to remove \the [tank] from \the [src] but it won't budge."))
				return
		if ("Toggle valve")
			if (!tank)
				to_chat(user, span_warning("There is no tank in \the [src]!"))
				return
			else
				if (valve_opened)
					src.visible_message(span_infoplain(span_bold("\The [user]") + " closes valve on \the [src]!"),
						span_notice("You close valve on \the [src]."))
					if(breather())
						breather().internals?.icon_state = "internal0"
						breather().internal = null
					valve_opened = FALSE
					update_icon()
				else
					src.visible_message(span_infoplain(span_bold("\The [user]") + " opens valve on \the [src]!"),
										span_notice("You open valve on \the [src]."))
					if(breather())
						breather().internal = tank
						breather().internals?.icon_state = "internal1"
					valve_opened = TRUE
					update_icon()
					om_task_periodic(src, PERIODIC_SLOW)
		if ("Remove vessel")
			if(beaker)
				beaker.forceMove(loc)
				beaker = null
				update_icon()

/obj/structure/medical_stand/proc/medical_stand_toggle_mode_effect(mob/user, obj/item/held, datum/interaction/interaction)

	if(!isliving(user))
		to_chat(user, span_warning("You can't do that."))
		return

	if(user.incapacitated())
		return

	mode = !mode
	to_chat(user, "The IV drip is now [mode ? "injecting" : "taking blood"].")

/obj/structure/medical_stand/proc/set_APTFT_effect(mob/user, obj/item/held, datum/interaction/interaction)
	om_ask(user, /datum/om/prompt/choice/medical_stand_transfer, PROC_REF(transfer_amount_chosen), choices = transfer_amounts)

/obj/structure/medical_stand/proc/transfer_amount_chosen(datum/om/prompt/choice/medical_stand_transfer/ask)
	var/N = ask.choice
	if(N)
		transfer_amount = N

/obj/structure/medical_stand/proc/attach_mask(mob/living/carbon/C)
	if(C && istype(C))
		if(C.equip_to_slot_if_possible(contained, SLOT_ID_MASK))
			if(tank)
				tank.forceMove(C)
			breather_handle = om_handle(C)
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
/obj/structure/medical_stand/proc/medical_stand_interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(istype(W, /obj/item/tank))
		if(tank)
			to_chat(user, span_warning("\The [src] already has a tank installed!"))
		else if(!is_loosen)
			to_chat(user, span_warning("Loosen the nut with a wrench first."))
		else
			user.drop_item()
			W.forceMove(src)
			tank = W
			user.visible_message(span_bold("\The [user]") + " attaches \the [tank] to \the [src].", span_notice("You attach \the [tank] to \the [src]."))
			src.add_fingerprint(user)
			update_icon()
		return TRUE

	if (istype(W, /obj/item/reagent_containers))
		if(!isnull(src.beaker))
			to_chat(user, "There is already a reagent container loaded!")
			return TRUE
		user.drop_item()
		W.forceMove(src)
		beaker = W
		to_chat(user, "You attach \the [W] to \the [src].")
		update_icon()
		return TRUE
	return FALSE

/obj/structure/medical_stand/wrench_act(mob/user, obj/item/W)
	if(valve_opened)
		to_chat(user, span_warning("Close the valve first."))
		return TRUE
	if(!tank)
		to_chat(user, span_warning("There is no tank in \the [src]."))
		return TRUE
	is_loosen = !is_loosen
	user.visible_message(
		span_notice("The [user] [is_loosen ? "loosens" : "tightens"] the nut holding [tank] in place."),
		span_notice("You [is_loosen ? "loosen" : "tighten"] the nut holding [tank] in place."))
	return TRUE

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

/obj/structure/medical_stand/periodic_step()
	//Gas Stuff
	if(breather())
		if(!can_apply_to_target(breather()))
			if(tank)
				tank.forceMove(src)
			if (breather().get_equipped_item(SLOT_ID_MASK) == contained)
				breather().remove_from_mob(contained)
				contained.forceMove(src)
			else
				qdel(contained)
				contained = new mask_type (src)
			src.visible_message(span_bold("\The [contained]") + " slips to \the [src]!")
			breather_handle = null
			update_icon()
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
			attached_handle = null
			update_icon()

	if(beaker)
		if(mode) // Give blood
			if(beaker.volume > 0)
				beaker.reagents.trans_to_mob(attached(), transfer_amount, CHEM_BLOOD)
				update_icon()
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
				update_icon()

	if ((!valve_opened || tank.distribute_pressure == 0) && !breather() && !attached())
		return PROCESS_KILL

/obj/structure/medical_stand/anesthetic
	spawn_type = /obj/item/tank/anesthetic
	mask_type = /obj/item/clothing/mask/breath/medical
	is_loosen = FALSE

DECLARE_DEFAULT_CHILD(/obj/structure/medical_stand, "tank", "spawn_type")
DECLARE_DEFAULT_CHILD(/obj/structure/medical_stand, "contained", "mask_type")

/// LC-refs: breather -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/structure/medical_stand/proc/breather() as /mob/living/carbon/human
	return om_resolve(breather_handle)

/// LC-refs: attached -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/structure/medical_stand/proc/attached() as /mob/living/carbon
	return om_resolve(attached_handle)

/// Old object verbs.
EXTEND_INTERACTIONS(/obj/structure/medical_stand, \
	INTERACT_VERB("Toggle IV Mode", PROC_REF(medical_stand_toggle_mode_effect)), \
	INTERACT_VERB("Set IV transfer amount", PROC_REF(set_APTFT_effect)), \
)
