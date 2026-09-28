
//The advanced pea-green monochrome lcd of tomorrow.

/obj/item/pda
	name = "\improper PDA"
	desc = "A portable microcomputer by Thinktronic Systems, LTD. Functionality determined by a preprogrammed ROM cartridge."
	icon = 'icons/obj/pda_vr.dmi'
	icon_state = "pda"
	item_state = "electronic"
	w_class = ITEMSIZE_SMALL
	slot_flags = SLOT_ID | SLOT_BELT
	sprite_sheets = list(SPECIES_TESHARI = 'icons/mob/species/teshari/id.dmi')

	//Main variables
	var/pdachoice = 1
	var/owner = null
	var/default_cartridge = 0 // Access level defined by cartridge
	var/obj/item/cartridge/cartridge = null //current cartridge

	//Secondary variables
	var/model_name = "Thinktronic 5230 Personal Data Assistant"
	var/tmp/scanmode_handle

	var/lock_code = "" // Lockcode to unlock uplink

	var/honkamt = 0 //How many honks left when infected with honk.exe
	var/mimeamt = 0 //How many silence left when infected with mime.exe
	var/detonate = 1 // Can the PDA be blown up?
	var/ttone = "beep" //The ringtone!
	var/hidden = 0 // Is the PDA hidden from the PDA list?
	var/touch_silent = 0 //If 1, no beeps on interacting.

	var/obj/item/card/id/id = null //Making it possible to slot an ID card into the PDA so it can function as both.
	var/ownjob = null //related to above - this is assignment (potentially alt title)
	var/ownrank = null // this one is rank, never alt title

	var/obj/item/paicard/pai = null	// A slot for a personal AI device

	var/spam_proof = FALSE // If true, it can't be spammed by random events.

	var/tmp/current_app_handle
	var/tmp/lastapp_handle
	var/list/programs = list( // ALLOW(instance_list): d: edited in place per instance (1 writers)
		new/datum/data/pda/app/main_menu,
		new/datum/data/pda/app/notekeeper,
		new/datum/data/pda/app/timeclock, // Add the timeclock to default apps
		new/datum/data/pda/app/news,
		new/datum/data/pda/app/messenger,
		new/datum/data/pda/app/manifest,
		new/datum/data/pda/app/contracts,
		new/datum/data/pda/app/supply_orders,
		new/datum/data/pda/app/service_receipts,
		new/datum/data/pda/app/atmos_scanner,
		new/datum/data/pda/app/nerdle,
		new/datum/data/pda/app/game_launcher,
		new/datum/data/pda/utility/scanmode/notes,
		new/datum/data/pda/utility/flashlight)
	var/list/shortcut_cache
	var/list/shortcut_cat_order
	var/list/notifying_programs
	var/retro_mode = 0

	///Var for attack_self chain
	var/special_handling = FALSE

/obj/item/pda/examine(mob/user)
	. = ..()
	if(Adjacent(user))
		. += "The time [stationtime2text()] is displayed in the corner of the screen."

/obj/item/pda/item_ctrl_click(mob/user)
	if(can_use(user) && !issilicon(user))
		remove_pen()
		return
	..()

/// Old click_alt.
/obj/item/pda/proc/interaction_alt(mob/user, obj/item/held, datum/interaction/interaction)
	if(issilicon(user))
		return TRUE

	if ( can_use(user) )
		if(id)
			remove_id()
		else
			to_chat(user, span_notice("This PDA does not have an ID in it."))
	return TRUE

/obj/item/pda/proc/play_ringtone()
	var/S

	if(ttone in GLOB.device_ringtones)
		S = GLOB.device_ringtones[ttone]
	else
		S = 'sound/machines/twobeep.ogg'
	playsound(loc, S, 50, 1)
	for(var/mob/O in hearers(3, loc))
		O.show_message(text("[icon2html(src, O.client)] *[ttone]*"))

/obj/item/pda/proc/set_ringtone(mob/user)
	var/t = rerun_ask(user, "k99", PROC_REF(set_ringtone), args, /datum/om/prompt/text, message = "Please enter new ringtone", title = name, default = ttone)
	if(isnull(t))
		return
	if(in_range(src, user) && loc == user)
		if(t)
			if(item_hidden_uplink(src) && item_hidden_uplink(src).check_trigger(user, lowertext(t), lowertext(lock_code)))
				to_chat(user, "The PDA softly beeps.")
				close(user)
			else
				t = sanitize(copytext(t, 1, 20))
				ttone = t
			return 1
	else
		close(user)
	return 0

REGISTRY_MEMBERSHIP(/obj/item/pda, REGISTRY_PDAS)

/obj/item/pda/Initialize(mapload)
	. = ..()
	update_programs()
	if(default_cartridge)
		cartridge = new default_cartridge(src)
		cartridge.update_programs(src)
	new /obj/item/pen(src)

	if(ishuman(loc))
		var/mob/living/carbon/human/H = loc
		pdachoice = H.pdachoice
	else
		pdachoice = 1

	switch(pdachoice)
		if(1)
			icon = 'icons/obj/pda_vr.dmi'
			model_name = "Thinktronic 5230 Personal Data Assistant"
		if(2)
			icon = 'icons/obj/pda_slim.dmi'
			model_name = "Ward-Takahashi SlimFit™ Personal Data Assistant"
		if(3)
			icon = 'icons/obj/pda_old.dmi'
			model_name = "Thinktronic 5120 Personal Data Assistant"
		if(4)
			icon = 'icons/obj/pda_rugged.dmi'
			model_name = "Hephaestus WARDEN Personal Data Assistant"
		if(5)
			icon = 'icons/obj/pda_holo.dmi'
			model_name = "LunaCorp Holo-PDAssistant"
		if(6)
			icon = 'icons/obj/pda_wrist.dmi'
			item_state = icon_state
			item_icons = list(
				slot_belt_str = 'icons/mob/pda_wrist.dmi',
				slot_wear_id_str = 'icons/mob/pda_wrist.dmi',
				slot_gloves_str = 'icons/mob/pda_wrist.dmi'
			)
			desc = "A portable microcomputer by Thinktronic Systems, LTD. This model is a wrist-bound version."
			slot_flags = SLOT_ID | SLOT_BELT | SLOT_GLOVES
			sprite_sheets = list(
				SPECIES_TESHARI = 'icons/mob/species/teshari/pda_wrist.dmi',
				SPECIES_VR_TESHARI = 'icons/mob/species/teshari/pda_wrist.dmi',
			)
		if(7)
			icon = 'icons/obj/pda_slider.dmi'
			model_name = "Slider® Personal Data Assistant"
		if(8)
			icon = 'icons/obj/pda_vintage.dmi'
			model_name = "\[ERR:INVALID_MANUFACTURER_ID\] Personal Data Assistant"
			desc = "A vintage communication device. This device has been refitted for compatibility with modern messaging systems, ROM cartridges and ID cards. Despite its heavy modifications it does not feature voice communication."

		else
			icon = 'icons/obj/pda_old.dmi'
			log_runtime("Invalid switch for PDA, defaulting to old PDA icons. [pdachoice] chosen.")
	add_overlay("pda-pen")
	start_program(find_program(/datum/data/pda/app/main_menu))

/obj/item/pda/proc/can_use(mob/user)
	return (tgui_status(user, GLOB.tgui_inventory_state) == STATUS_INTERACTIVE)

/obj/item/pda/GetAccess()
	if(id)
		return id.GetAccess()
	else
		return ..()

/obj/item/pda/GetID()
	return id

/obj/item/pda/MouseDrop(obj/over_object, src_location, over_location)
	var/mob/M = usr
	if((!istype(over_object, /atom/movable/screen)) && can_use(usr))
		return attack_self(M)
	return

/obj/item/pda/proc/close(mob/user)
	SStgui.close_uis(src)

/// Old attack_self: open the PDA (or its uplink). Subtypes with special_handling fall through.
/obj/item/pda/proc/pda_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(special_handling)
		return FALSE
	if(active_uplink_check(user))
		return TRUE

	tgui_interact(user)
	return TRUE

/obj/item/pda/proc/start_program(datum/data/pda/P)
	if(P && ((P in programs) || (cartridge && (P in cartridge.programs))))
		return P.start()
	return 0

/obj/item/pda/proc/find_program(type)
	var/datum/data/pda/A = locate(type) in programs
	if(A)
		return A
	if(cartridge)
		A = locate(type) in cartridge.programs
		if(A)
			return A
	return null

// force the cache to rebuild on update_ui
/obj/item/pda/proc/update_shortcuts()
	LAZYCLEARLIST(shortcut_cache)

/obj/item/pda/proc/update_programs()
	for(var/datum/data/pda/P as anything in programs)
		P.pda_handle = om_handle(src)

/obj/item/pda/proc/detonate_act(obj/item/pda/P)
	//TODO: sometimes these attacks show up on the message server
	var/i = rand(1,100)
	var/j = rand(0,1) //Possibility of losing the PDA after the detonation
	var/message = ""
	var/mob/living/M = null
	if(ismob(P.loc))
		M = P.loc

	//switch(i) //Yes, the overlapping cases are intended.
	if(i<=10) //The traditional explosion
		P.explode()
		j=1
		message += "Your [P] suddenly explodes!"
	if(i>=10 && i<= 20) //The PDA burns a hole in the holder.
		j=1
		if(M && isliving(M))
			M.injure(INJURY_BURN, rand(30,60), null, P)
		message += "You feel a searing heat! Your [P] is burning!"
	if(i>=20 && i<=25) //EMP
		empulse(P.loc, 1, 2, 4, 6, 1)
		message += "Your [P] emits a wave of electromagnetic energy!"
	if(i>=25 && i<=40) //Smoke
		var/datum/effect/effect/system/smoke_spread/chem/S = new /datum/effect/effect/system/smoke_spread/chem
		S.attach(P.loc)
		S.set_up(P, 10, 0, P.loc)
		playsound(P, 'sound/effects/smoke.ogg', 50, 1, -3)
		S.start()
		message += "Large clouds of smoke billow forth from your [P]!"
	if(i>=40 && i<=45) //Bad smoke
		var/datum/effect/effect/system/smoke_spread/bad/B = new /datum/effect/effect/system/smoke_spread/bad
		B.attach(P.loc)
		B.set_up(P, 10, 0, P.loc)
		playsound(P, 'sound/effects/smoke.ogg', 50, 1, -3)
		B.start()
		message += "Large clouds of noxious smoke billow forth from your [P]!"
	if(i>=65 && i<=75) //Weaken
		if(M && isliving(M))
			M.apply_effects(0,1)
		message += "Your [P] flashes with a blinding white light! You feel weaker."
	if(i>=75 && i<=85) //Stun and stutter
		if(M && isliving(M))
			M.apply_effects(1,0,0,0,1)
		message += "Your [P] flashes with a blinding white light! You feel weaker."
	if(i>=85) //Sparks
		var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
		s.set_up(2, 1, P.loc)
		s.start()
		message += "Your [P] begins to spark violently!"
	if(i>45 && i<65 && prob(50)) //Nothing happens
		message += "Your [P] bleeps loudly."
		j = prob(10)

	if(j && detonate) //This kills the PDA
		qdel(P)
		if(message)
			message += "It melts in a puddle of plastic."
		else
			message += "Your [P] shatters in a thousand pieces!"

	if(M && isliving(M))
		message = span_warning("[message]")
		M.show_message(message, 1)

/obj/item/pda/proc/remove_id()
	if (id)
		if (ismob(loc))
			var/mob/M = loc
			M.put_in_hands(id)
			to_chat(usr, span_notice("You remove the ID from the [name]."))
			playsound(src, 'sound/machines/id_swipe.ogg', 100, 1)
		else
			id.forceMove(get_turf(src))
		cut_overlay("pda-id")
		id = null

/obj/item/pda/proc/remove_pen()
	var/obj/item/pen/O = locate() in src
	if(O)
		if(istype(loc, /mob))
			var/mob/M = loc
			if(M.get_active_hand() == null)
				M.put_in_hands(O)
				to_chat(usr, span_notice("You remove \the [O] from \the [src]."))
				cut_overlay("pda-pen")
				return
		O.forceMove(get_turf(src))
	else
		to_chat(usr, span_notice("This PDA does not have a pen in it."))

/// Old Reset PDA verb.
/obj/item/pda/proc/pda_verb_reset(mob/user, obj/item/held, datum/interaction/interaction)
	if(issilicon(user))
		return

	if(can_use(user))
		start_program(find_program(/datum/data/pda/app/main_menu))
		LAZYCLEARLIST(notifying_programs)
		cut_overlay("pda-r")
		to_chat(user, span_notice("You press the reset button on \the [src]."))
	else
		to_chat(user, span_notice("You cannot do this while restrained."))

/// Old Remove id verb.
/obj/item/pda/proc/pda_verb_remove_id(mob/user, obj/item/held, datum/interaction/interaction)
	if(issilicon(user))
		return

	if ( can_use(user) )
		if(id)
			remove_id()
		else
			to_chat(user, span_notice("This PDA does not have an ID in it."))
	else
		to_chat(user, span_notice("You cannot do this while restrained."))

/// Old Remove pen verb.
/obj/item/pda/proc/pda_verb_remove_pen(mob/user, obj/item/held, datum/interaction/interaction)
	if(issilicon(user))
		return

	if ( can_use(user) )
		remove_pen()
	else
		to_chat(user, span_notice("You cannot do this while restrained."))

/// Old Remove cartridge verb.
/obj/item/pda/proc/pda_verb_remove_cartridge(mob/user, obj/item/held, datum/interaction/interaction)
	if(issilicon(user))
		return

	if(!can_use(user))
		to_chat(user, span_notice("You cannot do this while restrained."))
		return

	if(isnull(cartridge))
		to_chat(user, span_notice("There's no cartridge to eject."))
		return

	cartridge.forceMove(get_turf(src))
	if(ismob(loc))
		var/mob/M = loc
		M.put_in_hands(cartridge)
	// mode = 0
	// scanmode = 0
	if (cartridge.radio)
		cartridge.radio.hostpda_handle = null
	to_chat(user, span_notice("You remove \the [cartridge] from the [name]."))
	playsound(src, 'sound/machines/id_swipe.ogg', 100, 1)
	cartridge = null
	update_programs()
	update_shortcuts()
	start_program(find_program(/datum/data/pda/app/main_menu))

/obj/item/pda/proc/id_check(mob/user, choice)//To check for IDs; 1 for in-pda use, 2 for out of pda use.
	if(choice == 1)
		if (id)
			remove_id()
			return 1
		else
			var/obj/item/I = user.get_active_hand()
			if (istype(I, /obj/item/card/id) && user.unEquip(I))
				I.forceMove(src)
				id = I
			return 1
	else
		var/obj/item/card/I = user.get_active_hand()
		if (istype(I, /obj/item/card/id) && I:registered_name && user.unEquip(I))
			var/obj/old_id = id
			I.forceMove(src)
			id = I
			user.put_in_hands(old_id)
			return 1
	return 0

// access to status display signals
DECLARE_INTERACTIONS(/obj/item/pda, \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
	INTERACT_ALT(null, PROC_REF(interaction_alt)), \
	INTERACT_SELF(null, PROC_REF(pda_self)), \
	INTERACT_VERB("Reset PDA", PROC_REF(pda_verb_reset), REQ_IN_INVENTORY), \
	INTERACT_VERB("Remove id", PROC_REF(pda_verb_remove_id), REQ_IN_INVENTORY), \
	INTERACT_VERB("Remove pen", PROC_REF(pda_verb_remove_pen), REQ_IN_INVENTORY), \
	INTERACT_VERB("Remove cartridge", PROC_REF(pda_verb_remove_cartridge), REQ_IN_INVENTORY), \
)

/// Old attackby.
/obj/item/pda/proc/interaction_item(mob/user, obj/item/C, datum/interaction/interaction)
	if(istype(C, /obj/item/cartridge) && !cartridge)
		cartridge = C
		user.drop_item()
		cartridge.forceMove(src)
		cartridge.update_programs(src)
		update_shortcuts()
		to_chat(user, span_notice("You insert [cartridge] into [src]."))
		if(cartridge.radio)
			cartridge.radio.hostpda_handle = om_handle(src)

	else if(istype(C, /obj/item/card/id))
		var/obj/item/card/id/idcard = C
		if(!idcard.registered_name)
			to_chat(user, span_notice("\The [src] rejects the ID."))
			return INTERACTION_HANDLED_PASS
		if(!owner)
			owner = idcard.registered_name
			ownjob = idcard.assignment
			ownrank = idcard.rank
			name = "PDA-[owner] ([ownjob])"
			to_chat(user, span_notice("Card scanned."))
		else
			//Basic safety check. If either both objects are held by user or PDA is on ground and card is in hand.
			if(((src in user.contents) && (C in user.contents)) || (istype(loc, /turf) && in_range(src, user) && (C in user.contents)) )
				if(id_check(user, 2))
					to_chat(user, span_notice("You put the ID into \the [src]'s slot."))
					add_overlay("pda-id")
			return INTERACTION_HANDLED_PASS
	else if(istype(C, /obj/item/paicard) && !src.pai)
		user.drop_item(src)
		pai = C
		to_chat(user, span_notice("You slot \the [C] into \the [src]."))
		SStgui.update_uis(src) // update all UIs attached to src
	else if(istype(C, /obj/item/pen))
		var/obj/item/pen/O = locate() in src
		if(O)
			to_chat(user, span_notice("There is already a pen in \the [src]."))
		else
			user.drop_item(C)
			C.forceMove(src)
			to_chat(user, span_notice("You slot \the [C] into \the [src]."))
			add_overlay("pda-pen")
	return INTERACTION_HANDLED_PASS

/obj/item/pda/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(istype(M, /mob/living/carbon) && scanmode())
		scanmode().scan_mob(M, user)
		return ITEM_INTERACT_SUCCESS

/obj/item/pda/afterattack(atom/A, mob/user, proximity)
	if(proximity && scanmode())
		scanmode().scan_atom(A, user)

/obj/item/pda/proc/explode() //This needs tuning. //Sure did.
	if(!src.detonate) return
	var/turf/T = get_turf(src.loc)
	if(T)
		T.hotspot_expose(700,125)
		explosion(T, 0, 0, 1, rand(1,2))
	return

REF_OWNED(/obj/item/pda, list("pai", "cartridge"))
REF_OWNED_LIST(/obj/item/pda, "programs")

// its ID drops out unless flagged to go with it.
/obj/item/pda/on_destroy(force)
	if (id && !delete_id && id.loc == src)
		id.forceMove(get_turf(loc))
	else
		QDEL_NULL(id)
	..()

//Some spare PDAs in a box
/obj/item/storage/box/PDAs
	name = "box of spare PDAs"
	desc = "A box of spare PDA microcomputers."
	icon = 'icons/obj/pda_vr.dmi'
	icon_state = "pdabox"

/obj/item/storage/box/PDAs/Initialize(mapload)
	. = ..()
	new /obj/item/pda(src)
	new /obj/item/pda(src)
	new /obj/item/pda(src)
	new /obj/item/pda(src)
	new /obj/item/cartridge/head(src)

	var/newcart = pick(	/obj/item/cartridge/engineering,
						/obj/item/cartridge/security,
						/obj/item/cartridge/medical,
						/obj/item/cartridge/signal/science,
						/obj/item/cartridge/quartermaster)
	new newcart(src)

// === merged from pda_vr.dm during hard-fork de-suffix (chain-verified, vr->ch order preserved) ===
/obj/item/pda
	var/delete_id = FALSE			//Guaranteed deletion of ID upon deletion of PDA

/obj/item/pda/multicaster/exploration
	owner = "Exploration Department" //CHOMP keep explo
	name = "Exploration Department (Relay)" //CHOMP keep explo
	cartridges_to_send_to = list(/obj/item/cartridge/explorer,/obj/item/cartridge/sar)

/obj/item/pda/centcom
	default_cartridge = /obj/item/cartridge/captain
	icon_state = "pda-h"
	detonate = 0
//	hidden = 1

/obj/item/pda/pathfinder
	default_cartridge = /obj/item/cartridge/explorer
	icon_state = "pda-transp"			//Might as well let this sprite actually get seen, otherwise it's going to be hidden forever.

/obj/item/pda/explorer
	default_cartridge = /obj/item/cartridge/explorer
	icon_state = "pda-explore"			//Explorer's can get the PF's old style instead, rather than re-using the detective PDA

/obj/item/pda/sar
	default_cartridge = /obj/item/cartridge/sar
	icon_state = "pda-sar"			//Gives FM's a distinct PDA of their own, rather than sharing with the bridge-secretary & CCO's.

/obj/item/pda/pilot
	icon_state = "pda-pilot"		//New sprites, but still no ROM cartridge or anything

REF_HELD(/obj/item/pda, "id")

/// LC-refs: the scanmode this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/item/pda/proc/scanmode() as /datum/data/pda/utility/scanmode
	return om_resolve(scanmode_handle)

/// LC-refs: the current_app this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/item/pda/proc/current_app() as /datum/data/pda/app
	return om_resolve(current_app_handle)

/// LC-refs: the lastapp this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/item/pda/proc/lastapp() as /datum/data/pda/app
	return om_resolve(lastapp_handle)
