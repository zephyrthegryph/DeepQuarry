/obj/item/paicard
	name = "personal AI device"
	icon = 'icons/obj/pda.dmi'
	icon_state = "pai"
	item_state = "electronic"
	w_class = ITEMSIZE_SMALL
	slot_flags = SLOT_BELT | SLOT_HOLSTER
	show_messages = 0
	preserve_item = 1

	var/obj/item/radio/borg/pai/radio
	var/mob/living/silicon/pai/pai
	var/image/screen_layer
	var/screen_color = "#00ff0d"
	var/current_emotion = 1
	COOLDOWN_DECLARE(notify_cooldown)
	var/screen_msg
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

	// Parts and upgrades
	var/panel_open = FALSE
	var/cell = PP_FUNCTIONAL				//critical- power
	var/processor = PP_FUNCTIONAL			//critical- the thinky part
	var/board = PP_FUNCTIONAL				//critical- makes everything work
	var/capacitor = PP_FUNCTIONAL			//critical- power processing
	var/projector = PP_FUNCTIONAL			//non-critical- affects unfolding
	var/emitter = PP_FUNCTIONAL				//non-critical- affects unfolding
	var/speech_synthesizer = PP_FUNCTIONAL	//non-critical- affects speech

	///Var for attack_self chain
	var/special_handling = FALSE
	var/selected_pai

	// Special modules
	var/emagged = FALSE
	var/has_emag_toolkit = TRUE
	var/obj/item/multitool/multitool
	var/obj/item/assembly/signaler/signaler

	//Currently selected SubSystem
	var/static/list/systems_list = list("pAI","MultiTool","Emag","Signaler")
	var/selected_system = "pAI"

CAPABILITIES(/obj/item/paicard)
	emag(then(PROC_REF(on_emag)), repeatable = TRUE, powered = FALSE)
	blast_contents()
	owns_one(nameof(multitool), /obj/item/multitool)
	owns_one(nameof(radio), /obj/item/radio/borg/pai)
	owns_one(nameof(signaler), /obj/item/assembly/signaler)
	interface("PAICard", title = "Personal AI Device")
	without("ui_open")
	op("preview", ui_act("preview", arg("ref", schema_text(4096))), then(PROC_REF(ui_act_preview)))
	op("clear_preview", ui_act("clear_preview"), then(PROC_REF(ui_act_clear_preview)))
	op("setdna", ui_act("setdna"), then(PROC_REF(ui_act_setdna)))
	op("cleardna", ui_act("cleardna"), then(PROC_REF(ui_act_cleardna)))
	op("wires", ui_act("wires", arg("wires", num())), then(PROC_REF(ui_act_wires)))
	op("setlaws", ui_act("setlaws", arg("directive", schema_text(4096))), then(PROC_REF(ui_act_setlaws)))
	op("clearlaws", ui_act("clearlaws"), then(PROC_REF(ui_act_clearlaws)))
	op("select_pai", ui_act("select_pai", arg("ref", schema_text(4096))), then(PROC_REF(ui_act_select_pai)))
	op("select_tool", ui_act("select_tool", arg("tool")), then(PROC_REF(ui_act_select_tool)))
	op("activate_tool", ui_act("activate_tool"), then(PROC_REF(ui_act_activate_tool)))

/obj/item/paicard/relaymove(mob/user, direction)
	if(user.stat || user.has_status(EFFECT_STUNNED))
		return
	var/obj/item/rig/rig = src.get_rig()
	if(istype(rig))
		rig.forced_move(direction, user)

/obj/item/paicard/Initialize(mapload)
	. = ..()
	setEmotion(16)

// the pAI dies with its card (no throwing friend pAIs into the singularity to respawn).
/obj/item/paicard/on_destroy(force)
	if(!QDELETED(pai))
		pai.death(0)
	..()

/// Requirement: a wrecked (empty) card can't be activated.
/obj/item/paicard/proc/can_inhabit(mob/user, atom/target, obj/item/held)
	if(!pai && is_damage_critical())
		return "that card is too damaged to activate"
	return TRUE

/// Old attack_ghost: a ghost loads itself into an empty card. An occupied card falls to the ghost's default.
/obj/item/paicard/proc/paicard_observer_inhabit(mob/user, obj/item/held, datum/interaction/interaction)
	if(pai) //Have a person in them already?
		return FALSE
	var/time_till_respawn = user.time_till_respawn()
	if(time_till_respawn == -1) // Special case, never allowed to respawn
		to_chat(user, span_warning("Respawning is not allowed!"))
	else if(time_till_respawn) // Nonzero time to respawn
		to_chat(user, span_warning("You can't do that yet! You died too recently. You need to wait another [round(time_till_respawn/10/60, 0.1)] minutes."))
		return TRUE
	if(jobban_isbanned(user, JOB_PAI))
		to_chat(user,span_warning("You cannot join a pAI card when you are banned from playing as a pAI."))
		return TRUE

	if(SSpai.check_is_already_pai(user.ckey))
		to_chat(user, span_warning("You can't just rejoin any old pAI card!!! Your card still exists."))
		return TRUE

	var/pai_name = user.client?.prefs.read_preference(/datum/preference/text/pai_name)
	if(!pai_name || pai_name == PAI_UNSET)
		to_chat(user, span_danger("You have no pai name set."))
		return TRUE

	open_request(src, /datum/prompt/choice/pai_inhabit, PROC_REF(inhabit_confirmed), answerer = user, question = "Do you want to inhabit this pAI using \"[pai_name]\"?")
	return TRUE

/// A ghost loading into an empty card. Re-checked on the answer: still has a client, the card is still empty.
/datum/prompt/choice/pai_inhabit
	title = "Load pAI"
	choices = list("Load pAI Data", "Cancel")
	buttons = TRUE
	timeout = 0

/datum/prompt/choice/pai_inhabit/recheck_extra()
	if(!istype(answerer, /mob) || !answerer.client)
		return "nobody is playing it"
	var/obj/item/paicard/card = owner
	return card.pai ? "already inhabited" : null

/obj/item/paicard/proc/inhabit_confirmed(datum/act/request/A)
	if(A.answer?.value == "Load pAI Data")
		ghost_inhabit(A.request.answerer)

/obj/item/paicard/proc/ghost_inhabit(mob/user)
	RETURN_TYPE(/mob/living/silicon/pai)
	var/pai_name = user.client?.prefs.read_preference(/datum/preference/text/pai_name)
	if(!pai_name || pai_name == PAI_UNSET) // Lets avoid "None Set" pais joining
		to_chat(user, span_danger("You have no pai name set."))
		return
	// Setup pai
	var/mob/living/silicon/pai/new_pai = new(src)
	new_pai.key = user.key
	GLOB.paikeys |= new_pai.ckey
	setPersonality(new_pai)
	new_pai.apply_preferences(new_pai.client)
	return new_pai

/obj/item/paicard/ui_prepare(mob/user, datum/tgui/ui)
	if(is_damage_critical())
		to_chat(user, span_warning("WARNING: CRITICAL HARDWARE FAILURE, SERVICE DEVICE IMMEDIATELY"))
		return FALSE

	return TRUE

/obj/item/paicard/ui_assets(mob/user)
	return list(
		get_asset_datum(/datum/asset/spritesheet_batched/pai_icons),
	)

/// /obj/item/paicard's window data.
/obj/item/paicard/ui_data(datum/act/eval/A)
	var/list/data = list(
		"active_pai_data" = null,
		"selected_pai_data" = null,
		"available_pais" = null,
		"waiting_for_response" = in_use,
		"emag_systems" = null,
	)

	if(pai) // Only set pai data if we have one
		data["active_pai_data"] = get_active_data()
		return data

	if(selected_pai)
		data["selected_pai_data"] = SSpai.get_detailed_invite_data(selected_pai)
	// Only get the invite list if we can browse for them
	data["available_pais"] = SSpai.get_invite_list_data()
	return data

/obj/item/paicard/proc/get_active_data()
	var/list/radio_data
	if(radio)
		radio_data = list(
			"radio_transmit" = radio.broadcasting,
			"radio_recieve" = radio.listening,
		)

	var/list/emag_data
	if(emagged && has_emag_toolkit) // Special pAI tools
		emag_data = list(
			"emag_systems" = systems_list,
			"selected_system" = selected_system
		)

	var/datum/asset/spritesheet_batched/pai_icons/spritesheet = get_asset_datum(/datum/asset/spritesheet_batched/pai_icons)
	var/datum/pai_sprite/sprite_datum = SSpai.chassis_data(pai.chassis_name)
	var/css_class = sanitize_css_class_name("[sprite_datum.type]")
	return list(
		"name" = pai.name,
		"color" = screen_color,
		"chassis" = pai.chassis_name,
		"health" = round(pai.vitality() * 100),
		"law_zero" = pai.pai_law0,
		"law_extra" = pai.pai_laws,
		"master_name" = pai.master,
		"master_dna" = pai.master_dna,
		"screen_msg" = screen_msg,
		"radio_data" = radio_data,
		"sprite_datum_class" = css_class,
		"sprite_datum_size" = spritesheet.icon_size_id(css_class + "S"), // just get the south icon's size, the rest will be the same
		"emag_data" = emag_data,
	)

/obj/item/paicard/proc/ui_gate(datum/act/op/A)
	var/mob/user = A.actor
	if(is_damage_critical())
		return FALSE
	add_fingerprint(user)
	return TRUE

/obj/item/paicard/proc/ui_act_preview(datum/act/op/A, ref)
	if(!ui_gate(A))
		return FALSE
	if(pai)
		return FALSE
	if(in_use)
		return FALSE
	var/new_selection = ref
	if(!istext(new_selection))
		return FALSE
	selected_pai = new_selection
	return TRUE

/obj/item/paicard/proc/ui_act_clear_preview(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	if(pai)
		return FALSE
	if(in_use)
		return FALSE
	selected_pai = null
	return TRUE

/obj/item/paicard/proc/ui_act_setdna(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(!pai)
		return FALSE
	if(pai.master_dna)
		return FALSE

	var/mob/M = user
	var/has_dna = FALSE
	if(istype(M, /mob/living/carbon))
		var/mob/living/carbon/carby = M
		var/datum/species/spec = carby.species
		has_dna = TRUE
		if(spec.flags & NO_DNA)
			has_dna = FALSE

	if(has_dna)
		var/datum/dna/dna = M.dna
		pai.master = M.real_name
		pai.master_dna = dna.unique_enzymes
		to_chat(pai, span_warning(span_large("You have been bound to a new master.")))
		return TRUE
	to_chat(user, span_notice("You don't have any DNA, or your DNA is incompatible with this device."))
	return FALSE

/obj/item/paicard/proc/ui_act_cleardna(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	if(!pai)
		return FALSE
	pai.master = null
	pai.master_dna = null
	return TRUE

/obj/item/paicard/proc/ui_act_wires(datum/act/op/A, wires)
	if(!ui_gate(A))
		return FALSE
	if(!pai)
		return FALSE
	switch(wires)
		if(4)
			radio.ToggleBroadcast()
			return TRUE
		if(2)
			radio.ToggleReception()
			return TRUE
	return FALSE

/obj/item/paicard/proc/ui_act_setlaws(datum/act/op/A, directive)
	if(!ui_gate(A))
		return FALSE
	if(!pai)
		return FALSE
	if(in_use)
		return FALSE
	var/newlaws = sanitize(directive, MAX_MESSAGE_LEN, FALSE, FALSE, TRUE)
	if(newlaws)
		pai.pai_laws = newlaws
		show_laws(TRUE)
	return TRUE

/obj/item/paicard/proc/ui_act_clearlaws(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	if(!pai)
		return FALSE
	pai.pai_laws = null
	return TRUE

/obj/item/paicard/proc/ui_act_select_pai(datum/act/op/A, ref)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(pai)
		return FALSE
	if(in_use)
		return FALSE
	in_use = TRUE
	SSpai.invite_ghost(user, ref, src)
	in_use = FALSE
	selected_pai = null
	return TRUE

/obj/item/paicard/proc/ui_act_select_tool(datum/act/op/A, tool)
	if(!ui_gate(A))
		return FALSE
	if(!emagged || !has_emag_toolkit)
		return FALSE
	var/new_tool = tool
	if(!(new_tool in systems_list))
		return FALSE
	selected_system = new_tool
	return TRUE

/obj/item/paicard/proc/ui_act_activate_tool(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(!emagged || !has_emag_toolkit || !selected_system)
		return FALSE
	switch(selected_system)
		if("MultiTool")
			multitool.attack_self(user)
			return TRUE
		if("Signaler")
			signaler.attack_self(user)
			return TRUE
	return FALSE

/obj/item/paicard/pre_attack(atom/A, mob/user, params)
	if(emagged && has_emag_toolkit)
		// Perform builtin tool actions if we have a emag system selected
		switch(selected_system)
			if("Emag")
				if(istype(A,/obj/machinery/door))
					return TRUE //for doors use the doorjack
				return emag_target(A, 1,user,src)
			if("MultiTool")
				A.attackby(multitool,user)
				return TRUE
			if("Signaler")
				A.attackby(signaler,user)
				return TRUE
	. = ..()

/obj/item/paicard/proc/show_laws(updated = FALSE)
	to_chat(pai, examine_block(span_notice((updated ? "Your supplemental directives have been updated. Your new" : "Your") + " directives are:") + "<br>" + "Prime Directive: [span_info(pai.pai_law0)]<br>Supplemental Directives: [span_info(pai.pai_laws)]"))

/obj/item/paicard/proc/setPersonality(mob/living/silicon/pai/personality)
	rel_set(src, nameof(pai), personality)
	setEmotion(1)

/obj/item/paicard/proc/removePersonality()
	rel_clear(src, nameof(pai))
	setEmotion(16)

/obj/item/paicard/proc/setEmotion(emotion)
	cut_overlays()
	spent(screen_layer)
	screen_layer = null
	switch(emotion)
		if(1) screen_layer = image(icon, "pai-neutral")
		if(2) screen_layer = image(icon, "pai-what")
		if(3) screen_layer = image(icon, "pai-happy")
		if(4) screen_layer = image(icon, "pai-cat")
		if(5) screen_layer = image(icon, "pai-extremely-happy")
		if(6) screen_layer = image(icon, "pai-face")
		if(7) screen_layer = image(icon, "pai-laugh")
		if(8) screen_layer = image(icon, "pai-sad")
		if(9) screen_layer = image(icon, "pai-angry")
		if(10) screen_layer = image(icon, "pai-silly")
		if(11) screen_layer = image(icon, "pai-nose")
		if(12) screen_layer = image(icon, "pai-smirk")
		if(13) screen_layer = image(icon, "pai-exclamation")
		if(14) screen_layer = image(icon, "pai-question")
		if(15) screen_layer = image(icon, "pai-blank")
		if(16) screen_layer = image(icon, "pai-off")

	screen_layer.color = pai ? pai.eye_color : initial(screen_color)
	add_overlay(screen_layer)
	current_emotion = emotion

/obj/item/paicard/proc/alertUpdate()
	if(pai)
		return
	if(!COOLDOWN_TIMELEFT(src, notify_cooldown))
		audible_message(span_notice("\The [src] flashes a message across its screen, \"Additional personalities available for download.\""), hearing_distance = world.view, runemessage = "bleeps!")
		COOLDOWN_START(src, notify_cooldown, 5 MINUTES)
/*
*/
/obj/item/paicard/see_emote(mob/living/M, text)
	if(pai && pai.client && !pai.canmove)
		var/rendered = span_message("[text]")
		pai.show_message(rendered, 2)
	..()

/obj/item/paicard/show_message(msg, type, alt, alt_type)
	if(pai && pai.client)
		var/rendered = span_message("[msg]")
		pai.show_message(rendered, type)
	..()

/obj/item/paicard/proc/clear_invite_overlay()
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	if(pai) // Don't wipe emotion if a pai was invited
		return
	setEmotion(16)

/obj/item/paicard/proc/interaction_item(mob/user, obj/item/I, datum/interaction/interaction)
	if(I.has_tool_quality(TOOL_SCREWDRIVER))
		if(panel_open)
			panel_open = FALSE
			act_message(user, src, others = span_notice("%U% secured %T%'s maintenance panel."))
			play_sfx(src, SFX_ITEMS_SCREWDRIVER)
		else if(pai)
			om_task_timed(user, 3 SECONDS, target = src, receiver = src, on_done = PROC_REF(attackby_timed_done), done_args = list(user))
	if(istype(I,/obj/item/robotanalyzer))
		if(!panel_open)
			to_chat(user, span_warning("The panel isn't open. You will need to unscrew it to open it."))
		else
			if(cell == PP_FUNCTIONAL)
				to_chat(user,"Power cell: " + span_notice("functional"))
			else if(cell == PP_BROKEN)
				to_chat(user,"Power cell: " + span_warning("damaged - CRITICAL"))
			else
				to_chat(user,"Power cell: " + span_warning("missing - CRITICAL"))

			if(processor == PP_FUNCTIONAL)
				to_chat(user,"Processor: " + span_notice("functional"))
			else if(processor == PP_BROKEN)
				to_chat(user,"Processor: " + span_warning("damaged - CRITICAL"))
			else
				to_chat(user,"Processor: " + span_warning("missing - CRITICAL"))

			if(board == PP_FUNCTIONAL)
				to_chat(user,"Board: " + span_notice("functional"))
			else if(board == PP_BROKEN)
				to_chat(user,"Board: " + span_warning("damaged - CRITICAL"))
			else
				to_chat(user,"Board: " + span_warning("missing - CRITICAL"))

			if(capacitor == PP_FUNCTIONAL)
				to_chat(user,"Capacitors: " + span_notice("functional"))
			else if(capacitor == PP_BROKEN)
				to_chat(user,"Capacitors: " + span_warning("damaged - CRITICAL"))
			else
				to_chat(user,"Capacitors: " + span_warning("missing - CRITICAL"))

			if(projector == PP_FUNCTIONAL)
				to_chat(user,"Projectors: " + span_notice("functional"))
			else if(projector == PP_BROKEN)
				to_chat(user,"Projectors: " + span_warning("damaged"))
			else
				to_chat(user,"Projectors: " + span_warning("missing"))

			if(emitter == PP_FUNCTIONAL)
				to_chat(user,"Emitters: " + span_notice("functional"))
			else if(emitter == PP_BROKEN)
				to_chat(user,"Emitters: " + span_warning("damaged"))
			else
				to_chat(user,"Emitters: " + span_warning("missing"))

			if(speech_synthesizer == PP_FUNCTIONAL)
				to_chat(user,"Speech Synthesizer: " + span_notice("functional"))
			else if(speech_synthesizer == PP_BROKEN)
				to_chat(user,"Speech Synthesizer: " + span_warning("damaged"))
			else
				to_chat(user,"Speech Synthesizer: " + span_warning("missing"))

	if(I.has_tool_quality(TOOL_MULTITOOL))
		if(!panel_open)
			to_chat(user, span_warning("You can't do that in this state."))
		else
			var/list/parts = list()
			if(cell != PP_MISSING)
				parts |= "cell"
			if(processor != PP_MISSING)
				parts |= "processor"
			if(board != PP_MISSING)
				parts |= "board"
			if(capacitor != PP_MISSING)
				parts |= "capacitor"
			if(projector != PP_MISSING)
				parts |= "projector"
			if(emitter != PP_MISSING)
				parts |= "emitter"
			if(speech_synthesizer != PP_MISSING)
				parts |= "speech synthesizer"

			open_request(src, /datum/prompt/choice, PROC_REF(check_part), answerer = user, title = "Check part", question = "Which part would you like to check?", choices = parts, ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE, timeout = 0)
	if(istype(I,/obj/item/paiparts/cell))
		if(cell == PP_MISSING)
			om_task_timed(user, 3 SECONDS, target = src, receiver = src, on_done = PROC_REF(attackby_timed_done2), done_args = list(I, user))
		else
			to_chat(user, span_warning("You would need to remove the installed [I] first!"))
	if(istype(I,/obj/item/paiparts/processor))
		if(processor == PP_MISSING)
			om_task_timed(user, 3 SECONDS, target = src, receiver = src, on_done = PROC_REF(attackby_timed_done3), done_args = list(I, user))
		else
			to_chat(user, span_warning("You would need to remove the installed [I] first!"))
	if(istype(I,/obj/item/paiparts/board))
		if(board == PP_MISSING)
			om_task_timed(user, 3 SECONDS, target = src, receiver = src, on_done = PROC_REF(attackby_timed_done4), done_args = list(I, user))
		else
			to_chat(user, span_warning("You would need to remove the installed [I] first!"))
	if(istype(I,/obj/item/paiparts/capacitor))
		if(capacitor == PP_MISSING)
			om_task_timed(user, 3 SECONDS, target = src, receiver = src, on_done = PROC_REF(attackby_timed_done5), done_args = list(I, user))
		else
			to_chat(user, span_warning("You would need to remove the installed [I] first!"))
	if(istype(I,/obj/item/paiparts/projector))
		if(projector == PP_MISSING)
			om_task_timed(user, 3 SECONDS, target = src, receiver = src, on_done = PROC_REF(attackby_timed_done6), done_args = list(I, user))
		else
			to_chat(user, span_warning("You would need to remove the installed [I] first!"))
	if(istype(I,/obj/item/paiparts/emitter))
		if(emitter == PP_MISSING)
			om_task_timed(user, 3 SECONDS, target = src, receiver = src, on_done = PROC_REF(attackby_timed_done7), done_args = list(I, user))
		else
			to_chat(user, span_warning("You would need to remove the installed [I] first!"))
	if(istype(I,/obj/item/paiparts/speech_synthesizer))
		if(speech_synthesizer == PP_MISSING)
			om_task_timed(user, 3 SECONDS, target = src, receiver = src, on_done = PROC_REF(attackby_timed_done8), done_args = list(I, user))
		else
			to_chat(user, span_warning("You would need to remove the installed [I] first!"))

	var/obj/item/card/id/ID = I.GetID()
	if(ID && pai)
		if (pai.idaccessible == 1)
			open_request(src, /datum/prompt/choice/pai_id_access, PROC_REF(id_access_chosen), answerer = user, question = "Do you wish to add access to [src] or remove access from [src]?", subject = I)
			return TRUE
		else if (pai.idaccessible == 0)
			to_chat(user, span_notice("[src] is not accepting access modifications at this time."))
			return TRUE
	return TRUE

/obj/item/paicard/proc/check_part(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/choice = A.answer.value
	switch(choice)
		if("cell")
			if(cell == PP_FUNCTIONAL)
				to_chat(user,"Power cell: " + span_notice("functional"))
			else if(speech_synthesizer == PP_BROKEN)
				to_chat(user,"Power cell: " + span_warning("damaged"))
			else
				to_chat(user,"Power cell: " + span_warning("missing"))

		if("processor")
			if(processor == PP_FUNCTIONAL)
				to_chat(user,"Processor: " + span_notice("functional"))
			else if(speech_synthesizer == PP_BROKEN)
				to_chat(user,"Processor: " + span_warning("damaged"))
			else
				to_chat(user,"Processor: " + span_warning("missing"))

		if("board")
			if(board == PP_FUNCTIONAL)
				to_chat(user,"Board: " + span_notice("functional"))
			else if(speech_synthesizer == PP_BROKEN)
				to_chat(user,"Board: " + span_warning("damaged"))
			else
				to_chat(user,"Board: " + span_warning("missing"))

		if("capacitor")
			if(capacitor == PP_FUNCTIONAL)
				to_chat(user,"Capacitors: " + span_notice("functional"))
			else if(speech_synthesizer == PP_BROKEN)
				to_chat(user,"Capacitors: " + span_warning("damaged"))
			else
				to_chat(user,"Capacitors: " + span_warning("missing"))

		if("projector")
			if(projector == PP_FUNCTIONAL)
				to_chat(user,"Projectors: " + span_notice("functional"))
			else if(speech_synthesizer == PP_BROKEN)
				to_chat(user,"Projectors: " + span_warning("damaged"))
			else
				to_chat(user,"Projectors: " + span_warning("missing"))

		if("emitter")
			if(emitter == PP_FUNCTIONAL)
				to_chat(user,"Emitters: " + span_notice("functional"))
			else if(speech_synthesizer == PP_BROKEN)
				to_chat(user,"Emitters: " + span_warning("damaged"))
			else
				to_chat(user,"Emitters: " + span_warning("missing"))

		if("speech synthesizer")
			if(speech_synthesizer == PP_FUNCTIONAL)
				to_chat(user,"Speech Synthesizer: " + span_notice("functional"))
			else if(speech_synthesizer == PP_BROKEN)
				to_chat(user,"Speech Synthesizer: " + span_warning("damaged"))
			else
				to_chat(user,"Speech Synthesizer: " + span_warning("missing"))


/obj/item/paicard/proc/attackby_timed_done(mob/user)
	panel_open = TRUE
	act_message(user, src, others = span_warning("%U% opened %T%'s maintenance panel."))
	play_sfx(src, SFX_ITEMS_SCREWDRIVER)
/obj/item/paicard/proc/attackby_timed_done2(obj/item/I, mob/user)
	var/part_name = "\the [I]"
	if(!consume(I, user))
		return
	act_message(user, src, MSG_SELF(span_notice("You install [part_name] into %T%.")), MSG_OTHERS(span_notice("%U% installs [part_name] into %T%.")))
	cell = PP_FUNCTIONAL
/obj/item/paicard/proc/attackby_timed_done3(obj/item/I, mob/user)
	var/part_name = "\the [I]"
	if(!consume(I, user))
		return
	act_message(user, src, MSG_SELF(span_notice("You install [part_name] into %T%.")), MSG_OTHERS(span_notice("%U% installs [part_name] into %T%.")))
	processor = PP_FUNCTIONAL
/obj/item/paicard/proc/attackby_timed_done4(obj/item/I, mob/user)
	var/part_name = "\the [I]"
	if(!consume(I, user))
		return
	act_message(user, src, MSG_SELF(span_notice("You install [part_name] into %T%.")), MSG_OTHERS(span_notice("%U% installs [part_name] into %T%.")))
	board = PP_FUNCTIONAL
/obj/item/paicard/proc/attackby_timed_done5(obj/item/I, mob/user)
	var/part_name = "\the [I]"
	if(!consume(I, user))
		return
	act_message(user, src, MSG_SELF(span_notice("You install [part_name] into %T%.")), MSG_OTHERS(span_notice("%U% installs [part_name] into %T%.")))
	capacitor = PP_FUNCTIONAL
/obj/item/paicard/proc/attackby_timed_done6(obj/item/I, mob/user)
	var/part_name = "\the [I]"
	if(!consume(I, user))
		return
	act_message(user, src, MSG_SELF(span_notice("You install [part_name] into %T%.")), MSG_OTHERS(span_notice("%U% installs [part_name] into %T%.")))
	projector = PP_FUNCTIONAL
/obj/item/paicard/proc/attackby_timed_done7(obj/item/I, mob/user)
	var/part_name = "\the [I]"
	if(!consume(I, user))
		return
	act_message(user, src, MSG_SELF(span_notice("You install [part_name] into %T%.")), MSG_OTHERS(span_notice("%U% installs [part_name] into %T%.")))
	emitter = PP_FUNCTIONAL
/obj/item/paicard/proc/attackby_timed_done8(obj/item/I, mob/user)
	var/part_name = "\the [I]"
	if(!consume(I, user))
		return
	act_message(user, src, MSG_SELF(span_notice("You install [part_name] into %T%.")), MSG_OTHERS(span_notice("%U% installs [part_name] into %T%.")))
	speech_synthesizer = PP_FUNCTIONAL

DECLARE_INTERACTIONS(/obj/item/paicard, \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_OBSERVER("Inhabit", PROC_REF(paicard_observer_inhabit), REQ_TARGET_STATE(/obj/item/paicard/proc/can_inhabit)), \
)

/// `held` is unused by paicard's own dispatch (always null through the resolver) - repurposed
/// as the old `callback` bypass arg, so sleevecard.dm's direct ..(user, TRUE) call still works.
/obj/item/paicard/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(special_handling && !held)
		return FALSE
	if(!panel_open)
		tgui_interact(user)
		return
	var/list/parts = list()
	if(cell != PP_MISSING)
		parts |= "cell"
	if(processor != PP_MISSING)
		parts |= "processor"
	if(board != PP_MISSING)
		parts |= "board"
	if(capacitor != PP_MISSING)
		parts |= "capacitor"
	if(projector != PP_MISSING)
		parts |= "projector"
	if(emitter != PP_MISSING)
		parts |= "emitter"
	if(speech_synthesizer != PP_MISSING)
		parts |= "speech synthesizer"

	open_request(src, /datum/prompt/choice, PROC_REF(part_to_remove_chosen), answerer = user, title = "Remove part", question = "Which part would you like to remove?", choices = parts, ask_flags = ASK_CARRIED | ASK_CAPABLE, timeout = 0)
	return TRUE

/obj/item/paicard/proc/part_to_remove_chosen(datum/act/request/A)
	if(!A.answer)
		return
	if(!panel_open)
		return
	var/mob/user = A.request.answerer
	play_sfx(src, SFX_ITEMS_PICKUP_COMPONENT, volume = 0)
	om_task_timed(user, 3 SECONDS, target = src, receiver = src, on_done = PROC_REF(attack_self_timed_done), done_args = list(user, A.answer.value))

/// Adding or removing an ID's access. Re-checked on the answer: the ID is still in hand, the pAI still accepts it.
/datum/prompt/choice/pai_id_access
	buttons = TRUE
	choices = list("Add Access", "Remove Access", "Cancel")
	ask_flags = ASK_HELD | ASK_CAPABLE
	timeout = 0

/datum/prompt/choice/pai_id_access/recheck_extra()
	var/obj/item/I = subject
	var/obj/item/paicard/card = owner
	if(!I.GetID() || !card.pai || card.pai.idaccessible != 1)
		return "no access to change"
	return null

/obj/item/paicard/proc/id_access_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/obj/item/I = A.request.subject
	var/obj/item/card/id/ID = I.GetID()
	switch(A.answer.value)
		if("Add Access")
			pai.idcard.access |= ID.access
			to_chat(user, span_notice("You add the access from the [I] to [src]."))
		if("Remove Access")
			pai.idcard.access = list()
			to_chat(user, span_notice("You remove the access from [src]."))

/obj/item/paicard/proc/attack_self_timed_done(mob/user, choice)
	switch(choice)
		if("cell")
			if(cell == PP_FUNCTIONAL)
				new /obj/item/paiparts/cell(get_turf(user))
			else
				new /obj/item/paiparts(get_turf(user))
			act_message(user, src, MSG_SELF(span_warning("You remove \the [choice] from %T%.")), MSG_OTHERS(span_warning("%U% removes \the [choice] from %T%.")))
			cell = PP_MISSING
		if("processor")
			if(processor == PP_FUNCTIONAL)
				new /obj/item/paiparts/processor(get_turf(user))
			else
				new /obj/item/paiparts(get_turf(user))
			act_message(user, src, MSG_SELF(span_warning("You remove \the [choice] from %T%.")), MSG_OTHERS(span_warning("%U% removes \the [choice] from %T%.")))
			processor = PP_MISSING
		if("board")
			if(board == PP_FUNCTIONAL)
				new /obj/item/paiparts/board(get_turf(user))
			else
				new /obj/item/paiparts(get_turf(user))
			board = PP_MISSING
			act_message(user, src, MSG_SELF(span_warning("You remove \the [choice] from %T%.")), MSG_OTHERS(span_warning("%U% removes \the [choice] from %T%.")))

		if("capacitor")
			if(capacitor == PP_FUNCTIONAL)
				new /obj/item/paiparts/capacitor(get_turf(user))
			else
				new /obj/item/paiparts(get_turf(user))
			act_message(user, src, MSG_SELF(span_warning("You remove \the [choice] from %T%.")), MSG_OTHERS(span_warning("%U% removes \the [choice] from %T%.")))
			capacitor = PP_MISSING
		if("projector")
			if(projector == PP_FUNCTIONAL)
				new /obj/item/paiparts/projector(get_turf(user))
			else
				new /obj/item/paiparts(get_turf(user))
			act_message(user, src, MSG_SELF(span_warning("You remove \the [choice] from %T%.")), MSG_OTHERS(span_warning("%U% removes \the [choice] from %T%.")))
			projector = PP_MISSING
		if("emitter")
			if(emitter == PP_FUNCTIONAL)
				new /obj/item/paiparts/emitter(get_turf(user))
			else
				new /obj/item/paiparts(get_turf(user))
			act_message(user, src, MSG_SELF(span_warning("You remove \the [choice] from %T%.")), MSG_OTHERS(span_warning("%U% removes \the [choice] from %T%.")))
			emitter = PP_MISSING
		if("speech synthesizer")
			if(speech_synthesizer == PP_FUNCTIONAL)
				new /obj/item/paiparts/speech_synthesizer(get_turf(user))
			else
				new /obj/item/paiparts(get_turf(user))
			act_message(user, src, MSG_SELF(span_warning("You remove \the [choice] from %T%.")), MSG_OTHERS(span_warning("%U% removes \the [choice] from %T%.")))
			speech_synthesizer = PP_MISSING

/obj/item/paicard/proc/death_damage()
	var/number = rand(1,4)
	while(number)
		number --
		switch(rand(1,4))
			if(1)
				cell = PP_BROKEN
			if(2)
				processor = PP_BROKEN
			if(3)
				board = PP_BROKEN
			if(4)
				capacitor = PP_BROKEN

/obj/item/paicard/proc/damage_random_component(nonfatal = FALSE)
	fx_sparks(src, 2)
	if(prob(80) || nonfatal)	//Way more likely to be non-fatal part damage
		switch(rand(1,3))
			if(1)
				projector = PP_BROKEN
			if(2)
				emitter = PP_BROKEN
			if(3)
				speech_synthesizer = PP_BROKEN
	else
		switch(rand(1,4))
			if(1)
				cell = PP_BROKEN
			if(2)
				processor = PP_BROKEN
			if(3)
				board = PP_BROKEN
			if(4)
				capacitor = PP_BROKEN

/obj/item/paicard/proc/is_damage_critical()
	if(cell != PP_FUNCTIONAL || processor != PP_FUNCTIONAL || board != PP_FUNCTIONAL || capacitor != PP_FUNCTIONAL)
		return TRUE
	return FALSE

/obj/item/paicard/proc/on_emag(datum/act/op/A)
	var/mob/user = A.actor
	if(!pai)
		if(!emagged)
			to_chat(user, span_warning("Without a pAI inhabiting \the [src] nothing happens."))
		return OP_DECLINE
	if(!emagged)
		if(user)
			to_chat(user, span_notice("\The [src] buzzes and beeps."))
			play_sfx(src, SFX_MACHINES_BUZZBEEP)
		emagged = TRUE
		// Add tools
		if(has_emag_toolkit)
			rel_set(src, nameof(multitool), new /obj/item/multitool(src))
			rel_set(src, nameof(signaler), new /obj/item/assembly/signaler(src))
		return OP_OK
	return OP_DECLINE

///////////////////////////////
//////////pAI Parts  //////////
///////////////////////////////
/obj/item/paiparts
	name = "broken pAI component"
	desc = "It's broken scrap from a pAI card!"
	icon = 'icons/obj/paicard.dmi'
	icon_state = "broken"
	pickup_sound = SFX_ITEMS_PICKUP_CARD
	drop_sound = SFX_ITEMS_DROP_CARD

CAPABILITIES(/obj/item/paiparts)
	rolls(ROLL_PIXEL, PIXEL_JITTER(10))

/obj/item/paiparts/cell
	name = "pAI power cell"
	desc = "It's very small and efficient! It powers the pAI!"
	icon_state = "cell"

/obj/item/paiparts/processor
	name = "pAI processor"
	desc = "It's the brain of your computer friend!"
	icon_state = "processor"

/obj/item/paiparts/board
	name = "pAI board"
	desc = "It's the thing all the other parts get attatched to!"
	icon_state = "board"

/obj/item/paiparts/capacitor
	name = "pAI capacitor"
	desc = "It helps regulate power flow!"
	icon_state = "capacitor"

/obj/item/paiparts/projector
	name = "pAI projector"
	desc = "It projects the pAI's form!"
	icon_state = "projector"

/obj/item/paiparts/emitter
	name = "pAI emitter"
	desc = "It emits the fields to help the pAI get around!"
	icon_state = "emitter"

/obj/item/paiparts/speech_synthesizer
	name = "pAI speech synthesizer"
	desc = "It's a little voice box!"
	icon_state = "speech_synthesizer"

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// This adds a var and proc for all machines to take a pAI. (The pAI can't control anything, it's just for RP.)
// You need to add usage of the proc to each machine to actually add support. For an example of this, see code\modules\food\kitchen\microwave.dm
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
/obj/machinery
	var/obj/item/paicard/paicard = null

/obj/machinery/proc/insertpai(mob/user, obj/item/paicard/card)
	var/mob/living/silicon/pai/AI = card.pai
	if(paicard)
		to_chat(user, span_notice("This bot is already under PAI Control!"))
		return
	if(!istype(card)) // TODO: Add sleevecard support.
		return
	if(!card.pai)
		to_chat(user, span_notice("This card does not currently have a personality!"))
		return
	if(!move_into(src, nameof(src.paicard), card, user))
		return
	AI.reset_perspective(src) // focus this machine
	to_chat(AI, span_notice("Your location is [card.loc].")) // DEBUG. TODO: Make unfolding the chassis trigger an eject.
	name = AI.name
	to_chat(AI, span_notice("You feel a tingle in your circuits as your systems interface with \the [initial(src.name)]."))

/obj/machinery/proc/ejectpai(mob/user)
	if(paicard)
		paicard.forceMove(get_turf(src))
		var/mob/living/silicon/pai/AI = paicard.pai
		AI.reset_perspective() // return to the card
		own_take(src, nameof(paicard))
		name = initial(src.name)
		to_chat(AI, span_notice("You feel a tad claustrophobic as your mind closes back into your card, ejecting from \the [initial(src.name)]."))
		if(user)
			to_chat(user, span_notice("You eject the card from \the [initial(src.name)]."))

///////////////////////////////
//////////pAI Radios//////////
///////////////////////////////
//Thanks heroman!

/obj/item/radio/borg/pai
	name = "integrated radio"
	icon = 'icons/obj/robot_component.dmi' // Cyborgs radio icons should look like the component.
	icon_state = "radio"
	loudspeaker = FALSE

/// Old attackby was an empty stub, replacing radio/borg's own (no ..() chain): always swallowed, no action.
/obj/item/radio/borg/pai/declare_interactions(list/into)
	into += dq_interaction_from_spec(type, INTERACT_ITEM(null, PROC_REF(interaction_item)))

/obj/item/radio/borg/pai/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	return TRUE

/obj/item/radio/borg/pai/recalculateChannels()
	if(!istype(loc,/obj/item/paicard))
		return
	var/obj/item/paicard/card = loc
	secure_radio_connections = null // ALLOW(ownership): channel name -> the radio service's shared frequency datum (the service owns it; keyed by name, so not a relation list)
	channels = list()

	for(var/internal_chan in internal_channels)
		var/ch_name = GLOB.radio_channels_by_freq[internal_chan]
		if(has_channel_access(card.pai, internal_chan))
			channels += ch_name
			channels[ch_name] = 1
			LAZYSET(secure_radio_connections, ch_name, SSradio.add_object(src, GLOB.radiochannels[ch_name],  RADIO_CHAT)) // ALLOW(ownership): channel name -> the radio service's shared frequency datum (the service owns it; keyed by name, so not a relation list)

/obj/item/paicard/typeb
	name = "personal AI device"
	icon = 'icons/obj/paicard.dmi'

/obj/random/paicard
	name = "personal AI device spawner"
	icon = 'icons/obj/paicard.dmi'
	icon_state = "pai"

DECLARE_LOOT(/obj/random/paicard, LOOT_TABLE(/obj/item/paicard, /obj/item/paicard/typeb))

/obj/item/paicard/digest_act(atom/movable/item_storage = null)
	if(pai?.digestable)
		return ..()

/obj/machinery/ownership()
	. = ..()
	. += owns(nameof(paicard), policy = OWN_CONTAINED)

