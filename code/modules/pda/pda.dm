
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
	var/tmp/datum/data/pda/utility/scanmode/scanmode

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

	var/tmp/datum/data/pda/app/current_app
	var/tmp/datum/data/pda/app/lastapp
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

CAPABILITIES(/obj/item/pda)
	// Ten seconds of threatening to make it disappear in front of its owner (obj/item/proc/threat_eaten, code/game/objects/trash_eating.dm).
	op("threaten_eat", ai(), wait(10 SECONDS), then(PROC_REF(threat_eaten)))
	owns_one(nameof(cartridge), /obj/item/cartridge, starts = nameof(default_cartridge))
	owns_one(nameof(pai), /obj/item/paicard)
	drag_onto(PROC_REF(mousedrop_input))
	interface("Pda", title = "Personal Data Assistant", state = nameof(GLOB.tgui_inventory_state), forwards = nameof(current_app), pressed = PROC_REF(pda_pressed))
	without("ui_open")
	op("Home", ui_act("Home"), then(PROC_REF(ui_act_home)))
	op("StartProgram", ui_act("StartProgram", arg("program", schema_ref(/datum/data/pda/app))), then(PROC_REF(ui_act_startprogram)))
	op("Eject", ui_act("Eject"), then(PROC_REF(ui_act_eject)))
	op("Authenticate", ui_act("Authenticate"), then(PROC_REF(ui_act_authenticate)))
	op("Retro", ui_act("Retro"), then(PROC_REF(ui_act_retro)))
	op("TouchSounds", ui_act("TouchSounds"), then(PROC_REF(ui_act_touchsounds)))
	op("Ringtone", ui_act("Ringtone"), then(PROC_REF(ui_act_ringtone)))
	op("vv_fakepdapropconvo", topic_in(VV_TOPIC, VV_HK_FAKE_CONVO), needs(req_rights(R_FUN)), then(PROC_REF(vv_topic_fake_convo)))
	op("item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), then(PROC_REF(interaction_item)))
	op("alt", hand(), ungated(), gesture(GESTURE_ALT), priority(OP_PRIORITY_DEFAULT - 1), when(req_actor_kind(/mob/living/silicon, not = TRUE)), then(PROC_REF(interaction_alt)))
	op("pda_self", in_hand(), priority(OP_PRIORITY_DEFAULT - 1), then(PROC_REF(pda_self)))
	op("pda_verb_reset", menu(), priority(OP_PRIORITY_DEFAULT - 1), label("Reset PDA"), when(req_actor_kind(/mob/living/silicon, not = TRUE)), needs(carried()), then(PROC_REF(pda_verb_reset)))
	op("pda_verb_remove_id", menu(), priority(OP_PRIORITY_DEFAULT - 1), label("Remove id"), when(req_actor_kind(/mob/living/silicon, not = TRUE)), needs(carried()), then(PROC_REF(pda_verb_remove_id)))
	op("pda_verb_remove_pen", menu(), priority(OP_PRIORITY_DEFAULT - 1), label("Remove pen"), when(req_actor_kind(/mob/living/silicon, not = TRUE)), needs(carried()), then(PROC_REF(pda_verb_remove_pen)))
	op("pda_verb_remove_cartridge", menu(), priority(OP_PRIORITY_DEFAULT - 1), label("Remove cartridge"), when(req_actor_kind(/mob/living/silicon, not = TRUE)), needs(carried(), req(PROC_REF(can_remove_cartridge_holds), because = PROC_REF(can_remove_cartridge_refusal))), then(PROC_REF(pda_verb_remove_cartridge)))

/obj/item/pda/examine(mob/user)
	. = ..()
	if(Adjacent(user))
		. += "The time [stationtime2text()] is displayed in the corner of the screen."

/obj/item/pda/item_ctrl_click(mob/user)
	if(can_use(user) && !issilicon(user))
		remove_pen(user)
		return
	..()

/// Old click_alt.
/obj/item/pda/proc/interaction_alt(datum/act/op/A)
	var/mob/user = A.actor
	if ( can_use(user) )
		if(id)
			remove_id(user)
		else
			to_chat(user, span_notice("This PDA does not have an ID in it."))
	return OP_OK

/obj/item/pda/proc/play_ringtone()
	var/S

	if(ttone in GLOB.device_ringtones)
		S = GLOB.device_ringtones[ttone]
	else
		S = SFX_MACHINES_TWOBEEP
	playsound(loc, S, 50, 1)
	for(var/mob/O in hearers(3, loc))
		O.show_message(text("[icon2html(src, O.client)] *[ttone]*"))

/obj/item/pda/proc/set_ringtone(mob/user)
	open_request(src, /datum/prompt/text/pda_ringtone, PROC_REF(ringtone_answered), answerer = user, title = name, default = ttone)

/datum/prompt/text/pda_ringtone
	question = "Please enter new ringtone"
	max_len = MAX_MESSAGE_LEN
	encode = TRUE
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/text/pda_ringtone/recheck_extra()
	. = ..()
	if(.)
		return
	var/obj/item/pda/device = owner
	if(!istype(device) || QDELETED(device) || QDELETED(answerer))
		return "The PDA or user is no longer available."
	if(!isnull(value) && (!in_range(device, answerer) || device.loc != answerer))
		return "The PDA is not held by the user."

/obj/item/pda/proc/ringtone_answered(datum/act/request/A)
	var/mob/user = A.request.answerer
	if(!A.answer)
		if(!isnull(A.request.value) && !QDELETED(user))
			close(user)
			SStgui.update_uis(src)
		return
	apply_ringtone(user, A.answer.value)
	SStgui.update_uis(src)

/obj/item/pda/proc/apply_ringtone(mob/user, t)
	if(t)
		if(item_hidden_uplink(src) && item_hidden_uplink(src).check_trigger(user, lowertext(t), lowertext(lock_code)))
			to_chat(user, "The PDA softly beeps.")
			close(user)
		else
			t = sanitize(copytext(t, 1, 20))
			ttone = t
		return 1
	return 0

REGISTRY_MEMBERSHIP(/obj/item/pda, REGISTRY_PDAS)

/obj/item/pda/Initialize(mapload)
	. = ..()
	update_programs()
	cartridge?.update_programs(src) // declared child from default_cartridge
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

/// The native MouseDrop's actor and arguments, handed over by the engine (drag_onto(), code/engine/lifeforms/input.dm).
/obj/item/pda/proc/mousedrop_input(datum/act/input/A)
	return drop_with_actor(A.actor, A.over)

/obj/item/pda/proc/drop_with_actor(mob/user, obj/over_object)
	if((!istype(over_object, /atom/movable/screen)) && can_use(user))
		return attack_self(user)
	return

/obj/item/pda/proc/close(mob/user)
	SStgui.close_uis(src)

/// Old attack_self: open the PDA (or its uplink). Subtypes with special_handling fall through.
/obj/item/pda/proc/pda_self(datum/act/op/A)
	var/mob/user = A.actor
	if(special_handling)
		return OP_DECLINE
	if(active_uplink_check(user))
		return OP_OK

	tgui_interact(user)
	return OP_OK

/obj/item/pda/proc/start_program(datum/data/pda/P)
	if(P && ((P in programs) || (cartridge && (P in cartridge.programs))))
		return P.start()
	return 0

/obj/item/pda/proc/find_program(type)
	var/datum/data/pda/A = locate_in_list(programs, type)
	if(A)
		return A
	if(cartridge)
		A = locate_in_list(cartridge.programs, type)
		if(A)
			return A
	return null

// force the cache to rebuild on update_ui
/obj/item/pda/proc/update_shortcuts()
	LAZYCLEARLIST(shortcut_cache)

/obj/item/pda/proc/update_programs()
	for(var/datum/data/pda/P as anything in programs)
		rel_set(P, nameof(P.pda), src)

/obj/item/pda/proc/detonate_act(obj/item/pda/P)
	//TODO: sometimes these attacks show up on the message server
	var/i = rand(1,100)
	var/j = rand(0,1) //Possibility of losing the PDA after the detonation
	var/message = ""
	var/mob/living/M = null
	if(ismob(P.loc))
		M = P.loc

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
		play_sfx(P, SFX_EFFECTS_SMOKE)
		S.start()
		message += "Large clouds of smoke billow forth from your [P]!"
	if(i>=40 && i<=45) //Bad smoke
		var/datum/effect/effect/system/smoke_spread/bad/B = new /datum/effect/effect/system/smoke_spread/bad
		B.attach(P.loc)
		B.set_up(P, 10, 0, P.loc)
		play_sfx(P, SFX_EFFECTS_SMOKE)
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
		fx_sparks(P.loc, 2)
		message += "Your [P] begins to spark violently!"
	if(i>45 && i<65 && prob(50)) //Nothing happens
		message += "Your [P] bleeps loudly."
		j = prob(10)

	if(j && detonate) //This kills the PDA
		destroyed(P, null, "explosion")
		if(message)
			message += "It melts in a puddle of plastic."
		else
			message += "Your [P] shatters in a thousand pieces!"

	if(M && isliving(M))
		message = span_warning("[message]")
		M.show_message(message, 1)

/obj/item/pda/proc/remove_id(mob/user)
	if (id)
		if (ismob(loc))
			var/mob/M = loc
			M.put_in_hands(id)
			to_chat(user, span_notice("You remove the ID from the [name]."))
			play_sfx(src, SFX_MACHINES_ID_SWIPE, 2)
		else
			id.forceMove(get_turf(src))
		cut_overlay("pda-id")
		rel_take(src, nameof(id))

/obj/item/pda/proc/remove_pen(mob/user)
	var/obj/item/pen/O = locate_within(src, /obj/item/pen)
	if(O)
		if(istype(loc, /mob))
			var/mob/M = loc
			if(M.get_active_hand() == null)
				M.put_in_hands(O)
				to_chat(user, span_notice("You remove \the [O] from \the [src]."))
				cut_overlay("pda-pen")
				return
		O.forceMove(get_turf(src))
	else
		to_chat(user, span_notice("This PDA does not have a pen in it."))

/// Old Reset PDA verb.
/obj/item/pda/proc/pda_verb_reset(datum/act/op/A)
	var/mob/user = A.actor
	if(can_use(user))
		start_program(find_program(/datum/data/pda/app/main_menu))
		rel_clear(src, nameof(notifying_programs))
		cut_overlay("pda-r")
		to_chat(user, span_notice("You press the reset button on \the [src]."))
	else
		to_chat(user, span_notice("You cannot do this while restrained."))

/// Old Remove id verb.
/obj/item/pda/proc/pda_verb_remove_id(datum/act/op/A)
	var/mob/user = A.actor
	if ( can_use(user) )
		if(id)
			remove_id(user)
		else
			to_chat(user, span_notice("This PDA does not have an ID in it."))
	else
		to_chat(user, span_notice("You cannot do this while restrained."))

/// Old Remove pen verb.
/obj/item/pda/proc/pda_verb_remove_pen(datum/act/op/A)
	var/mob/user = A.actor
	if ( can_use(user) )
		remove_pen(user)
	else
		to_chat(user, span_notice("You cannot do this while restrained."))

/// Requirement: TRUE, or why the cartridge can't be ejected. Silicons are turned away silently by the verb.
/obj/item/pda/proc/can_remove_cartridge_reason(mob/user)
	if(!can_use(user))
		return "you cannot do this while restrained"
	if(isnull(cartridge))
		return "there's no cartridge to eject"
	return null

/// Requirement: the cartridge can be ejected.
/obj/item/pda/proc/can_remove_cartridge_holds(datum/act/op/A)
	return isnull(can_remove_cartridge_reason(A.actor))

/// Why can_remove_cartridge_holds refuses.
/obj/item/pda/proc/can_remove_cartridge_refusal(datum/act/op/A)
	return can_remove_cartridge_reason(A.actor)


/obj/item/pda/proc/pda_verb_remove_cartridge(datum/act/op/A)
	var/mob/user = A.actor
	cartridge.forceMove(get_turf(src))
	if(ismob(loc))
		var/mob/M = loc
		M.put_in_hands(cartridge)
	if (cartridge.radio)
		rel_clear(cartridge.radio, nameof(/obj/item/radio/integrated::hostpda))
	to_chat(user, span_notice("You remove \the [cartridge] from the [name]."))
	play_sfx(src, SFX_MACHINES_ID_SWIPE, 2)
	rel_take(src, nameof(cartridge))
	update_programs()
	update_shortcuts()
	start_program(find_program(/datum/data/pda/app/main_menu))

/obj/item/pda/proc/id_check(mob/user, choice)//To check for IDs; 1 for in-pda use, 2 for out of pda use.
	if(choice == 1)
		if (id)
			remove_id(user)
			return 1
		else
			var/obj/item/I = user.get_active_hand()
			if (istype(I, /obj/item/card/id))
				move_into(src, nameof(src.id), I, user)
			return 1
	else
		var/obj/item/card/I = user.get_active_hand()
		if (istype(I, /obj/item/card/id) && I:registered_name)
			var/obj/old_id = rel_take(src, nameof(src.id)) // handed back below, not disposed of
			if(!move_into(src, nameof(src.id), I, user))
				rel_set(src, nameof(src.id), old_id)
				return 0
			user.put_in_hands(old_id)
			return 1
	return 0

// access to status display signals

/// Old attackby.
/obj/item/pda/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/C = A.held
	if(istype(C, /obj/item/cartridge) && !cartridge)
		if(!move_into(src, nameof(src.cartridge), C, user))
			return OP_PASS
		cartridge.update_programs(src)
		update_shortcuts()
		to_chat(user, span_notice("You insert [cartridge] into [src]."))
		if(cartridge.radio)
			rel_set(cartridge.radio, nameof(/obj/item/radio/integrated::hostpda), src)

	else if(istype(C, /obj/item/card/id))
		var/obj/item/card/id/idcard = C
		if(!idcard.registered_name)
			to_chat(user, span_notice("\The [src] rejects the ID."))
			return OP_PASS
		if(!owner)
			owner = idcard.registered_name
			ownjob = idcard.assignment
			ownrank = idcard.rank
			name = "PDA-[owner] ([ownjob])"
			to_chat(user, span_notice("Card scanned."))
		else
			//Basic safety check. If either both objects are held by user or PDA is on ground and card is in hand.
			if(((src?.loc == user) && (C?.loc == user)) || (istype(loc, /turf) && in_range(src, user) && (C?.loc == user)) )
				if(id_check(user, 2))
					to_chat(user, span_notice("You put the ID into \the [src]'s slot."))
					add_overlay("pda-id")
			return OP_PASS
	else if(istype(C, /obj/item/paicard) && !src.pai)
		if(!move_into(src, nameof(src.pai), C, user))
			return OP_PASS
		to_chat(user, span_notice("You slot \the [C] into \the [src]."))
		SStgui.update_uis(src) // update all UIs attached to src
	else if(istype(C, /obj/item/pen))
		var/obj/item/pen/O = locate_within(src, /obj/item/pen)
		if(O)
			to_chat(user, span_notice("There is already a pen in \the [src]."))
		else
			if(!own_bring_in(src, nameof(contents), C, null, user, TRUE, null, FALSE))
				return OP_PASS
			to_chat(user, span_notice("You slot \the [C] into \the [src]."))
			add_overlay("pda-pen")
	return OP_PASS

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



//Some spare PDAs in a box
/obj/item/storage/box/PDAs
	name = "box of spare PDAs"
	desc = "A box of spare PDA microcomputers."
	icon = 'icons/obj/pda_vr.dmi'
	icon_state = "pdabox"

// ALLOW(init/INSTANCE_STATE): rolls the department cartridge this box carries
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

// Its ID drops out when it is destroyed, unless flagged (delete_id) to go with it.
/obj/item/pda/ownership()
	. = ..()
	. += owns(nameof(id), policy = OWN_DELETE, if_var = nameof(delete_id), else_policy = OWN_SPILL)

/// The scanmode this refers to (a relation view: null once that is deleted).
/obj/item/pda/proc/scanmode() as /datum/data/pda/utility/scanmode
	return scanmode

/// The current_app this refers to (a relation view: null once that is deleted).
/obj/item/pda/proc/current_app() as /datum/data/pda/app
	return current_app

/// The lastapp this refers to (a relation view: null once that is deleted).
/obj/item/pda/proc/lastapp() as /datum/data/pda/app
	return lastapp
