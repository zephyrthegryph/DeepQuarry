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
TRACKED(/obj/machinery/suit_storage_unit, isUV)
TRACKED(/obj/machinery/suit_storage_unit, islocked)
TRACKED(/obj/machinery/suit_storage_unit, issuperUV)

CAPABILITIES(/obj/machinery/suit_storage_unit)
	owns_one(nameof(HELMET), /obj/item/clothing/head/helmet/space, starts = nameof(helmet_type))
	owns_one(nameof(MASK), /obj/item/clothing/mask, starts = nameof(mask_type))
	owns_one(nameof(SUIT), /obj/item/clothing/suit/space, starts = nameof(suit_type))
	extend(/datum/act/hit/explosion, instead(then(PROC_REF(suit_storage_blast))))
	interface("SuitStorageUnit", state = nameof(GLOB.tgui_notcontained_state))
	op("door", ui_act("door"), then(PROC_REF(ui_act_door)))
	op("dispense", ui_act("dispense", arg("item", schema_text(4096))), then(PROC_REF(ui_act_dispense)))
	op("uv", ui_act("uv"), then(PROC_REF(ui_act_uv)))
	op("lock", ui_act("lock"), then(PROC_REF(ui_act_lock)))
	op("eject_guy", ui_act("eject_guy"), then(PROC_REF(ui_act_eject_guy)))
	op("toggleUV", ui_act("toggleUV"), then(PROC_REF(ui_act_toggleuv)))
	op("togglesafeties", ui_act("togglesafeties"), then(PROC_REF(ui_act_togglesafeties)))
	extend(TAG_UI, needs(req(PROC_REF(ui_gate), silent = TRUE)))

/// Sealed occupant slot (C8a, containment.md §10). Suit, helmet and mask stay
/// their own typed vars -- only the person hiding inside is a slot.
/datum/om/relation/slot/occupant/suit_storage
	holder = /obj/machinery/suit_storage_unit
	slot_id = OCCUPANT_SLOT_SUIT_STORAGE
	name = "suit storage unit"

/obj/machinery/suit_storage_unit/proc/appearance_helmet()
	return HELMET ? 1 : 0

/obj/machinery/suit_storage_unit/proc/appearance_suit()
	return SUIT ? 1 : 0

/obj/machinery/suit_storage_unit/proc/appearance_human()
	return src?.slot_item(OCCUPANT_SLOT_SUIT_STORAGE) ? 1 : 0

/// The look (the draw sweep: from its template).
/obj/machinery/suit_storage_unit/draw(datum/look/look)
	..()
	look.state("suitstorage[appearance_helmet()][appearance_suit()][appearance_human()][isopen][islocked][isUV][ispowered][isbroken][issuperUV]")

/obj/machinery/suit_storage_unit/power_change()
	. = ..()
	if(!has_stat(NOPOWER))
		ispowered = 1
	else
		after(src, rand(0, 15), PROC_REF(lose_power))

/// A heavy blast may throw the unit's contents out.
/obj/machinery/suit_storage_unit/proc/suit_storage_blast(datum/act/hit/explosion/A)
	var/datum/damage_packet/packet = A.packet
	if(packet.severity <= 2 && prob(50))
		dump_everything()
	return HOOK_DECLINE

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

/obj/machinery/suit_storage_unit/ui_data(datum/act/eval/A)
	var/mob/living/carbon/human/OCCUPANT = slot_item_real(OCCUPANT_SLOT_SUIT_STORAGE)
	var/list/data = list()


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
	data["broken"] = isbroken
	data["panelopen"] = panelopen
	data["locked"] = islocked
	data["open"] = isopen
	data["safeties"] = safetieson
	data["uv_active"] = isUV
	data["uv_super"] = issuperUV
	return data

/// The window answers while the unit is neither disinfecting nor broken.
/obj/machinery/suit_storage_unit/proc/ui_gate(datum/act/op/A)
	return !isUV && !isbroken // ALLOW(reads): the unit's state is read when a button is pressed, never from a cached menu

/obj/machinery/suit_storage_unit/proc/ui_act_door(datum/act/op/A)
	var/mob/user = A.actor
	toggle_open(user)
	. = TRUE
	add_fingerprint(user)

/obj/machinery/suit_storage_unit/proc/ui_act_dispense(datum/act/op/A, item)
	var/mob/user = A.actor
	switch(item)
		if("helmet")
			dispense_helmet(user)
		if("mask")
			dispense_mask(user)
		if("suit")
			dispense_suit(user)
	. = TRUE
	add_fingerprint(user)

/obj/machinery/suit_storage_unit/proc/ui_act_uv(datum/act/op/A)
	var/mob/user = A.actor
	start_UV(user)
	. = TRUE
	add_fingerprint(user)

/obj/machinery/suit_storage_unit/proc/ui_act_lock(datum/act/op/A)
	var/mob/user = A.actor
	toggle_lock(user)
	. = TRUE
	add_fingerprint(user)

/obj/machinery/suit_storage_unit/proc/ui_act_eject_guy(datum/act/op/A)
	var/mob/user = A.actor
	eject_occupant(user)
	. = TRUE

	// Panel Open stuff
	add_fingerprint(user)

/obj/machinery/suit_storage_unit/proc/ui_act_toggleuv(datum/act/op/A)
	var/mob/user = A.actor
	if(!panelopen)
		return FALSE
	toggleUV(user)
	. = TRUE
	add_fingerprint(user)

/obj/machinery/suit_storage_unit/proc/ui_act_togglesafeties(datum/act/op/A)
	var/mob/user = A.actor
	if(!panelopen)
		return FALSE
	togglesafeties(user)
	. = TRUE
	add_fingerprint(user)


/obj/machinery/suit_storage_unit/proc/toggleUV(mob/user as mob)
	if(!panelopen)
		return

	else  //welp, the guy is protected, we can continue
		if(issuperUV)
			to_chat(user, span_info("You slide the dial back towards \"185nm\"."))
			set_issuperUV(0)
		else
			to_chat(user, span_info("You crank the dial all the way up to \"15nm\"."))
			set_issuperUV(1)
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
		own_take(src, nameof(HELMET))
		return


/obj/machinery/suit_storage_unit/proc/dispense_suit(mob/user as mob)
	if(!SUIT)
		return
	else
		SUIT.forceMove(get_turf(src))
		own_take(src, nameof(SUIT))
		return


/obj/machinery/suit_storage_unit/proc/dispense_mask(mob/user as mob)
	if(!MASK)
		return
	else
		MASK.forceMove(get_turf(src))
		own_take(src, nameof(MASK))
		return


/obj/machinery/suit_storage_unit/proc/dump_everything()
	var/mob/living/carbon/human/OCCUPANT = src?.slot_item(OCCUPANT_SLOT_SUIT_STORAGE)
	set_islocked(0) //locks go free
	if(SUIT)
		SUIT.forceMove(get_turf(src))
		own_take(src, nameof(SUIT))
	if(HELMET)
		HELMET.forceMove(get_turf(src))
		own_take(src, nameof(HELMET))
	if(MASK)
		MASK.forceMove(get_turf(src))
		own_take(src, nameof(MASK))
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
	set_islocked(!islocked)
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
	set_isUV(1)
	if(OCCUPANT && !islocked)
		set_islocked(1) //Let's lock it for good measure
	changed(src)

	after(src, 5 SECONDS, PROC_REF(uv_cycle_step), with = list(0))

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
				destroyed(HELMET, src, BURN)
				own_take(src, nameof(HELMET))
			if(SUIT)
				destroyed(SUIT, src, BURN)
				own_take(src, nameof(SUIT))
			if(MASK)
				destroyed(MASK, src, BURN)
				own_take(src, nameof(MASK))
			visible_message(span_danger("With a loud whining noise, the Suit Storage Unit's door grinds open. Puffs of ashen smoke come out of its chamber."), 3)
			isbroken = 1
			isopen = 1
			set_islocked(0)
			eject_occupant(OCCUPANT) //Mixing up these two lines causes bug. DO NOT DO IT.
		set_isUV(0) //Cycle ends
	if(i < 3)
		after(src, 5 SECONDS, PROC_REF(uv_cycle_step), with = list(i + 1))
		return
	changed(src)

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
	changed(src)
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
	changed(src)
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
	if(!move_into(src, OCCUPANT_SLOT_SUIT_STORAGE, user, user))
		return TRUE
	isopen = 0 //Close the thing after the guy gets inside
	changed(src)

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
		if(!move_into(src, nameof(src.SUIT), S, user))
			return TRUE
		changed(src)
		return TRUE
	if(istype(I,/obj/item/clothing/head/helmet))
		if(!isopen)
			return TRUE
		var/obj/item/clothing/head/helmet/H = I
		if(HELMET)
			to_chat(user, span_notice("The unit already contains a helmet."))
			return TRUE
		to_chat(user, span_info("You load the [H.name] into the storage compartment."))
		if(!move_into(src, nameof(src.HELMET), H, user))
			return TRUE
		changed(src)
		return TRUE
	if(istype(I,/obj/item/clothing/mask))
		if(!isopen)
			return TRUE
		var/obj/item/clothing/mask/M = I
		if(MASK)
			to_chat(user, span_notice("The unit already contains a mask."))
			return TRUE
		to_chat(user, span_info("You load the [M.name] into the storage compartment."))
		if(!move_into(src, nameof(src.MASK), M, user))
			return TRUE
		changed(src)
		return TRUE
	changed(src)
	return TRUE

/obj/machinery/suit_storage_unit/proc/interaction_use_item_timed_done(mob/user, obj/item/grab/G)
	if(!G || !G?.grab_target()) return TRUE //derpcheck
	var/mob/M = G?.grab_target()
	if(!move_into(src, OCCUPANT_SLOT_SUIT_STORAGE, M, user))
		return TRUE
	isopen = 0 //close ittt

	add_fingerprint(user)
	consume(G, user)
	changed(src)
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
	set_islocked(0)
	isopen = 1
	dump_everything()
	changed(src)

