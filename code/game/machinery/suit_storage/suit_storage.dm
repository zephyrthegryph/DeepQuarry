//////////////////////////////////////
// SUIT STORAGE UNIT /////////////////
//////////////////////////////////////

/obj/machinery/suit_storage_unit
	name = "Suit Storage Unit"
	desc = "An industrial U-Stor-It Storage unit designed to accomodate all kinds of space suits. Its on-board equipment also allows the user to decontaminate the contents through a UV-ray purging cycle. There's a warning label dangling from the control pad, reading \"STRICTLY NO BIOLOGICALS IN THE CONFINES OF THE UNIT\"."
	icon = 'icons/obj/suit_storage.dmi'
	icon_state = "suitstorage000000100" //order is: [has helmet][has suit][has human][is open][is locked][is UV cycling][is powered][is dirty/broken] [is superUVcycling]
	anchored = TRUE
	density = TRUE
	var/obj/item/clothing/suit/space/SUIT = null
	var/suit_type = null
	var/obj/item/clothing/head/helmet/space/HELMET = null
	var/helmet_type = null
	var/obj/item/clothing/mask/MASK = null  //All the stuff that's gonna be stored insiiiiiiiiiiiiiiiiiiide, nyoro~n
	var/mask_type = null //Erro's idea on standarising SSUs whle keeping creation of other SSU types easy: Make a child SSU, name it something then set the TYPE vars to your desired suit output. New() should take it from there by itself.
	var/isopen = 0
	var/islocked = 0
	var/isUV = 0
	var/ispowered = 1 //starts powered
	var/isbroken = 0
	var/issuperUV = 0
	var/panelopen = 0
	var/safetieson = 1
	var/cycletime_left = 0

DECLARE_DEFAULT_CHILD(/obj/machinery/suit_storage_unit, "SUIT", "suit_type")
DECLARE_DEFAULT_CHILD(/obj/machinery/suit_storage_unit, "HELMET", "helmet_type")
DECLARE_DEFAULT_CHILD(/obj/machinery/suit_storage_unit, "MASK", "mask_type")

/obj/machinery/suit_storage_unit/Initialize(mapload)
	. = ..()
	update_icon()

/// Sealed occupant slot (C8a, containment.md §10). Suit, helmet and mask stay
/// their own typed vars -- only the person hiding inside is a slot.
/datum/om/relation/slot/occupant/suit_storage
	holder = /obj/machinery/suit_storage_unit
	slot_id = OCCUPANT_SLOT_SUIT_STORAGE
	name = "suit storage unit"

/obj/machinery/suit_storage_unit/update_icon()
	var/mob/living/carbon/human/OCCUPANT = src?.slot_item(OCCUPANT_SLOT_SUIT_STORAGE)
	var/hashelmet = 0
	var/hassuit = 0
	var/hashuman = 0
	if(HELMET)
		hashelmet = 1
	if(SUIT)
		hassuit = 1
	if(OCCUPANT)
		hashuman = 1
	icon_state = text("suitstorage[][][][][][][][][]", hashelmet, hassuit, hashuman, isopen, islocked, isUV, ispowered, isbroken, issuperUV)

/obj/machinery/suit_storage_unit/power_change()
	. = ..()
	if(!has_stat(NOPOWER))
		ispowered = 1
		update_icon()
	else
		om_after(src, rand(0, 15), PROC_REF(lose_power))

DAMAGE_REACTION(/obj/machinery/suit_storage_unit, DAMAGE_EXPLOSION, PROC_REF(suit_storage_blast))
/// A heavy blast may throw the unit's contents out.
/obj/machinery/suit_storage_unit/proc/suit_storage_blast(datum/damage_packet/packet)
	if(packet.severity <= 2 && prob(50))
		dump_everything()

/obj/machinery/suit_storage_unit/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_verb/suit_storage_get_out,
		/datum/interaction/machine_verb/suit_storage_move_inside,
		/datum/interaction/machine_item/suit_storage_use_item,
		/datum/interaction/machine_hand/suit_storage_use,
	)
	..()

/// The old attack_hand: called ..() first, then opened the UI if powered and dexterous.
/datum/interaction/machine_hand/suit_storage_use
	id = "suit_storage_use"
	name = "Use"
	effect = /obj/machinery/suit_storage_unit/proc/interaction_use

/obj/machinery/suit_storage_unit/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(has_stat(NOPOWER))
		return TRUE
	if(!user.IsAdvancedToolUser())
		return TRUE
	tgui_interact(user)
	return TRUE

/obj/machinery/suit_storage_unit/tgui_state(mob/user)
	return GLOB.tgui_notcontained_state

/obj/machinery/suit_storage_unit/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "SuitStorageUnit", name)
		ui.open()

/obj/machinery/suit_storage_unit/tgui_data()
	var/mob/living/carbon/human/OCCUPANT = slot_item_real(OCCUPANT_SLOT_SUIT_STORAGE)
	var/list/data = list()

	data["broken"] = isbroken
	data["panelopen"] = panelopen

	data["locked"] = islocked
	data["open"] = isopen
	data["safeties"] = safetieson
	data["uv_active"] = isUV
	data["uv_super"] = issuperUV
	if(HELMET)
		data["helmet"] = HELMET.name
	else
		data["helmet"] = null
	if(SUIT)
		data["suit"] = SUIT.name
	else
		data["suit"] = null
	if(MASK)
		data["mask"] = MASK.name
	else
		data["mask"] = null
	data["storage"] = null
	if(OCCUPANT)
		data["occupied"] = TRUE
	else
		data["occupied"] = FALSE
	return data

/obj/machinery/suit_storage_unit/tgui_act(action, params, datum/tgui/ui) //I fucking HATE this proc
	if(..() || isUV || isbroken)
		return TRUE

	switch(action)
		if("door")
			toggle_open(ui.user)
			. = TRUE
		if("dispense")
			switch(params["item"])
				if("helmet")
					dispense_helmet(ui.user)
				if("mask")
					dispense_mask(ui.user)
				if("suit")
					dispense_suit(ui.user)
			. = TRUE
		if("uv")
			start_UV(ui.user)
			. = TRUE
		if("lock")
			toggle_lock(ui.user)
			. = TRUE
		if("eject_guy")
			eject_occupant(ui.user)
			. = TRUE

	// Panel Open stuff
	if(!. && panelopen)
		switch(action)
			if("toggleUV")
				toggleUV(ui.user)
				. = TRUE
			if("togglesafeties")
				togglesafeties(ui.user)
				. = TRUE

	update_icon()
	add_fingerprint(ui.user)


/obj/machinery/suit_storage_unit/proc/toggleUV(mob/user as mob)
	if(!panelopen)
		return

	else  //welp, the guy is protected, we can continue
		if(issuperUV)
			to_chat(user, span_info("You slide the dial back towards \"185nm\"."))
			issuperUV = 0
		else
			to_chat(user, span_info("You crank the dial all the way up to \"15nm\"."))
			issuperUV = 1
		return


/obj/machinery/suit_storage_unit/proc/togglesafeties(mob/user as mob)
	if(!panelopen) //Needed check due to bugs
		return

	else
		to_chat(user, span_info("You push the button. The coloured LED next to it changes."))
		safetieson = !safetieson


/obj/machinery/suit_storage_unit/proc/dispense_helmet(mob/user as mob)
	if(!HELMET)
		return //Do I even need this sanity check? Nyoro~n
	else
		HELMET.forceMove(get_turf(src))
		own_take(src, "HELMET")
		return


/obj/machinery/suit_storage_unit/proc/dispense_suit(mob/user as mob)
	if(!SUIT)
		return
	else
		SUIT.forceMove(get_turf(src))
		own_take(src, "SUIT")
		return


/obj/machinery/suit_storage_unit/proc/dispense_mask(mob/user as mob)
	if(!MASK)
		return
	else
		MASK.forceMove(get_turf(src))
		own_take(src, "MASK")
		return


/obj/machinery/suit_storage_unit/proc/dump_everything()
	var/mob/living/carbon/human/OCCUPANT = src?.slot_item(OCCUPANT_SLOT_SUIT_STORAGE)
	islocked = 0 //locks go free
	if(SUIT)
		SUIT.forceMove(get_turf(src))
		own_take(src, "SUIT")
	if(HELMET)
		HELMET.forceMove(get_turf(src))
		own_take(src, "HELMET")
	if(MASK)
		MASK.forceMove(get_turf(src))
		own_take(src, "MASK")
	if(OCCUPANT)
		eject_occupant(OCCUPANT)
	return


/obj/machinery/suit_storage_unit/proc/toggle_open(mob/user)
	var/mob/living/carbon/human/OCCUPANT = src?.slot_item(OCCUPANT_SLOT_SUIT_STORAGE)
	if(islocked || isUV)
		to_chat(user, span_warning("Unable to open unit."))
		return
	if(OCCUPANT)
		eject_occupant(user)
		return  // eject_occupant opens the door, so we need to return
	isopen = !isopen
	return


/obj/machinery/suit_storage_unit/proc/toggle_lock(mob/user)
	var/mob/living/carbon/human/OCCUPANT = src?.slot_item(OCCUPANT_SLOT_SUIT_STORAGE)
	if(OCCUPANT && safetieson)
		to_chat(user, span_warning("The Unit's safety protocols disallow locking when a biological form is detected inside its compartments."))
		return
	if(isopen)
		return
	islocked = !islocked
	return


/obj/machinery/suit_storage_unit/proc/start_UV(mob/user)
	var/mob/living/carbon/human/OCCUPANT = src?.slot_item(OCCUPANT_SLOT_SUIT_STORAGE)
	if(isUV || isopen) //I'm bored of all these sanity checks
		return
	if(OCCUPANT && safetieson)
		to_chat(user, span_warning(span_bold("WARNING:") + "Biological entity detected in the confines of the Unit's storage. Cannot initiate cycle."))
		return
	if(!HELMET && !MASK && !SUIT && !OCCUPANT) //shit's empty yo
		to_chat(user, span_warning("Unit storage bays empty. Nothing to disinfect -- Aborting."))
		return
	to_chat(user, span_notice("You start the Unit's cauterisation cycle."))
	cycletime_left = 20
	isUV = 1
	if(OCCUPANT && !islocked)
		islocked = 1 //Let's lock it for good measure
	update_icon()

	om_after(src, 5 SECONDS, PROC_REF(uv_cycle_step), 0)

/// One five-second pass of the cauterisation cycle; pass 3 ends it.
/obj/machinery/suit_storage_unit/proc/uv_cycle_step(i)
	var/mob/living/carbon/human/OCCUPANT = src?.slot_item(OCCUPANT_SLOT_SUIT_STORAGE)
	if(OCCUPANT)
		OCCUPANT.apply_effect(50, IRRADIATE)
		var/obj/item/organ/internal/diona/nutrients/rad_organ = locate_in_list(OCCUPANT.internal_organ_list(), /obj/item/organ/internal/diona/nutrients)
		if(!rad_organ)
			if(OCCUPANT.can_feel_pain())
				OCCUPANT.emote("scream")
			if(issuperUV)
				var/burndamage = rand(28,35)
				OCCUPANT.injure(INJURY_BURN, burndamage, null, src)
			else
				var/burndamage = rand(6,10)
				OCCUPANT.injure(INJURY_BURN, burndamage, null, src)
	if(i==3) //End of the cycle
		if(!issuperUV)
			if(HELMET)
				HELMET.wash(CLEAN_SCRUB)
			if(SUIT)
				SUIT.wash(CLEAN_SCRUB)
			if(MASK)
				MASK.wash(CLEAN_SCRUB)
		else //It was supercycling, destroy everything
			if(HELMET)
				qdel(HELMET)
				own_take(src, "HELMET")
			if(SUIT)
				qdel(SUIT)
				own_take(src, "SUIT")
			if(MASK)
				qdel(MASK)
				own_take(src, "MASK")
			visible_message(span_danger("With a loud whining noise, the Suit Storage Unit's door grinds open. Puffs of ashen smoke come out of its chamber."), 3)
			isbroken = 1
			isopen = 1
			islocked = 0
			eject_occupant(OCCUPANT) //Mixing up these two lines causes bug. DO NOT DO IT.
		isUV = 0 //Cycle ends
	if(i < 3)
		om_after(src, 5 SECONDS, PROC_REF(uv_cycle_step), i + 1)
		return
	update_icon()

/obj/machinery/suit_storage_unit/proc/cycletimeleft()
	if(cycletime_left >= 1)
		cycletime_left--
	return cycletime_left


/obj/machinery/suit_storage_unit/proc/eject_occupant(mob/user as mob)
	var/mob/living/carbon/human/OCCUPANT = src?.slot_item(OCCUPANT_SLOT_SUIT_STORAGE)
	if(islocked)
		return

	if(!OCCUPANT)
		return

	if(OCCUPANT.client)
		if(user != OCCUPANT)
			to_chat(OCCUPANT, span_notice("The machine kicks you out!"))
		if(user.loc != src.loc)
			to_chat(OCCUPANT, span_notice("You leave the not-so-cozy confines of the SSU."))
	slot_remove(OCCUPANT, get_turf(src))
	if(!isopen)
		isopen = 1
	update_icon()
	return


/// The old "Eject Suit Storage Unit" object verb.
/datum/interaction/machine_verb/suit_storage_get_out
	id = "suit_storage_get_out"
	name = "Eject Suit Storage Unit"
	category = INTERACTION_CAT_EJECT
	requires = list(REQ_INTERACTION_REACH)
	effect = /obj/machinery/suit_storage_unit/proc/interaction_get_out

/obj/machinery/suit_storage_unit/proc/interaction_get_out(mob/user, obj/item/held, datum/interaction/interaction)
	if(user.stat != 0)
		return TRUE
	eject_occupant(user)
	add_fingerprint(user)
	update_icon()
	return TRUE

/// The old "Hide in Suit Storage Unit" object verb.
/datum/interaction/machine_verb/suit_storage_move_inside
	id = "suit_storage_move_inside"
	name = "Hide in Suit Storage Unit"
	requires = list(REQ_INTERACTION_REACH, REQ_TARGET_STATE(/obj/machinery/suit_storage_unit/proc/can_move_inside))
	effect = /obj/machinery/suit_storage_unit/proc/interaction_move_inside

/// Requirement for hiding inside: TRUE, or why not.
/obj/machinery/suit_storage_unit/proc/can_move_inside(mob/user, atom/target, obj/item/held)
	if(user.stat != CONSCIOUS)
		return TRUE // the effect declines silently
	if(!isopen)
		return "the unit's doors are shut"
	if(!ispowered || isbroken)
		return "the unit is not operational"
	if(slot_item(OCCUPANT_SLOT_SUIT_STORAGE) || HELMET || SUIT)
		return "it's too cluttered inside for you to fit in"
	return TRUE

/obj/machinery/suit_storage_unit/proc/interaction_move_inside(mob/user, obj/item/held, datum/interaction/interaction)
	if(user.stat != CONSCIOUS)
		return TRUE
	act_message(user, null, others = span_info("%U% starts squeezing into the suit storage unit!"))
	om_task_timed(user, 1 SECOND, target = src, receiver = src, on_done = PROC_REF(interaction_move_inside_timed_done), done_args = list(user))
	return TRUE

/obj/machinery/suit_storage_unit/proc/interaction_move_inside_timed_done(mob/user)
	user.stop_pulling()
	if(!user.move_into(src, OCCUPANT_SLOT_SUIT_STORAGE, user))
		return TRUE
	isopen = 0 //Close the thing after the guy gets inside
	update_icon()

	add_fingerprint(user)
	return TRUE

/// The old attackby: never called ..(), loaded a grabbed mob, suit, helmet or mask.
/datum/interaction/machine_item/suit_storage_use_item
	id = "suit_storage_use_item"
	name = "Load"
	held_type = /obj/item
	effect = /obj/machinery/suit_storage_unit/proc/interaction_use_item

/obj/machinery/suit_storage_unit/proc/interaction_use_item(mob/user, obj/item/I, datum/interaction/interaction)
	var/mob/living/carbon/human/OCCUPANT = src?.slot_item(OCCUPANT_SLOT_SUIT_STORAGE)
	if(!ispowered)
		return TRUE
	if(istype(I, /obj/item/grab))
		var/obj/item/grab/G = I
		var/mob/grabbed = G?.grab_target()
		if(!(ismob(grabbed)))
			return TRUE
		if(!isopen)
			to_chat(user, span_warning("The unit's doors are shut."))
			return TRUE
		if(!ispowered || isbroken)
			to_chat(user, span_warning("The unit is not operational."))
			return TRUE
		if((OCCUPANT) || (HELMET) || (SUIT)) //Unit needs to be absolutely empty
			to_chat(user, span_warning("The unit's storage area is too cluttered."))
			return TRUE
		act_message(user, null, others = span_notice("%U% starts putting [grabbed.name] into the Suit Storage Unit."))
		om_task_timed(user, 2 SECONDS, target = src, receiver = src, on_done = PROC_REF(interaction_use_item_timed_done), done_args = list(user, G))
		return TRUE
	if(istype(I,/obj/item/clothing/suit/space))
		if(!isopen)
			return TRUE
		var/obj/item/clothing/suit/space/S = I
		if(SUIT)
			to_chat(user, span_notice("The unit already contains a suit."))
			return TRUE
		to_chat(user, span_info("You load the [S.name] into the storage compartment."))
		user.drop_item()
		S.forceMove(src)
		own_set(src, "SUIT", S)
		update_icon()
		return TRUE
	if(istype(I,/obj/item/clothing/head/helmet))
		if(!isopen)
			return TRUE
		var/obj/item/clothing/head/helmet/H = I
		if(HELMET)
			to_chat(user, span_notice("The unit already contains a helmet."))
			return TRUE
		to_chat(user, span_info("You load the [H.name] into the storage compartment."))
		user.drop_item()
		H.forceMove(src)
		own_set(src, "HELMET", H)
		update_icon()
		return TRUE
	if(istype(I,/obj/item/clothing/mask))
		if(!isopen)
			return TRUE
		var/obj/item/clothing/mask/M = I
		if(MASK)
			to_chat(user, span_notice("The unit already contains a mask."))
			return TRUE
		to_chat(user, span_info("You load the [M.name] into the storage compartment."))
		user.drop_item()
		M.forceMove(src)
		own_set(src, "MASK", M)
		update_icon()
		return TRUE
	update_icon()
	return TRUE

/obj/machinery/suit_storage_unit/proc/interaction_use_item_timed_done(mob/user, obj/item/grab/G)
	if(!G || !G?.grab_target()) return TRUE //derpcheck
	var/mob/M = G?.grab_target()
	if(!M.move_into(src, OCCUPANT_SLOT_SUIT_STORAGE, user))
		return TRUE
	isopen = 0 //close ittt

	add_fingerprint(user)
	consume(G, user)
	update_icon()
	return TRUE

/obj/machinery/suit_storage_unit/screwdriver_act(mob/user, obj/item/tool)
	if(!ispowered)
		return ITEM_INTERACT_BLOCKING
	panelopen = !panelopen
	playsound(src, tool.usesound, 100, TRUE)
	to_chat(user, span_notice("You [panelopen ? "open up" : "close"] the unit's maintenance panel."))
	return ITEM_INTERACT_SUCCESS


//////////////////////////////REMINDER: Make it lock once you place some fucker inside.

//God this entire file is fucking awful //Yes

/obj/machinery/suit_storage_unit/proc/lose_power()
	ispowered = 0
	islocked = 0
	isopen = 1
	dump_everything()
	update_icon()

