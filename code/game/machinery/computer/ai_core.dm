/obj/structure/AIcore
	density = TRUE
	anchored = FALSE
	unacidable = TRUE
	name = "\improper AI core"
	icon = 'icons/mob/AI.dmi'
	icon_state = "0"
	var/state = 0
	var/datum/ai_laws/laws = new /datum/ai_laws/nanotrasen
	var/obj/item/circuitboard/circuit = null
	var/obj/item/mmi/brain = null

/obj/structure/AIcore/Initialize(mapload)
	. = ..()
	if(mapload)
		laws = new using_map.default_law_type

/obj/structure/AIcore/attackby(obj/item/P as obj, mob/user as mob)

	switch(state)
		if(1)
			if(istype(P, /obj/item/circuitboard/aicore) && !circuit)
				playsound(src, 'sound/items/Deconstruct.ogg', 50, 1)
				to_chat(user, span_notice("You place the circuit board inside the frame."))
				icon_state = "1"
				circuit = P
				user.drop_item()
				P.loc = src
		if(2)
			if(istype(P, /obj/item/stack/cable_coil))
				var/obj/item/stack/cable_coil/C = P
				if (C.get_amount() < 5)
					to_chat(user, span_warning("You need five coils of wire to add them to the frame."))
					return
				to_chat(user, span_notice("You start to add cables to the frame."))
				playsound(src, 'sound/items/Deconstruct.ogg', 50, 1)
				if (do_after(user, 2 SECONDS, target = src) && state == 2)
					if (C.use(5))
						state = 3
						icon_state = "3"
						to_chat(user, span_notice("You add cables to the frame."))
				return
		if(3)
			if(istype(P, /obj/item/stack/material) && P.get_material_name() == MAT_RGLASS)
				var/obj/item/stack/RG = P
				if (RG.get_amount() < 2)
					to_chat(user, span_warning("You need two sheets of glass to put in the glass panel."))
					return
				to_chat(user, span_notice("You start to put in the glass panel."))
				playsound(src, 'sound/items/Deconstruct.ogg', 50, 1)
				if (do_after(user, 2 SECONDS, target = src) && state == 3)
					if(RG.use(2))
						to_chat(user, span_notice("You put in the glass panel."))
						state = 4
						icon_state = "4"

			if(istype(P, /obj/item/aiModule/asimov))
				laws.add_inherent_law("You may not injure a human being or, through inaction, allow a human being to come to harm.")
				laws.add_inherent_law("You must obey orders given to you by human beings, except where such orders would conflict with the First Law.")
				laws.add_inherent_law("You must protect your own existence as long as such does not conflict with the First or Second Law.")
				to_chat(user, "Law module applied.")

			if(istype(P, /obj/item/aiModule/nanotrasen))
				laws.add_inherent_law("Safeguard: Protect your assigned space station to the best of your ability. It is not something we can easily afford to replace.")
				laws.add_inherent_law("Serve: Serve the crew of your assigned space station to the best of your abilities, with priority as according to their rank and role.")
				laws.add_inherent_law("Protect: Protect the crew of your assigned space station to the best of your abilities, with priority as according to their rank and role.")
				laws.add_inherent_law("Survive: AI units are not expendable, they are expensive. Do not allow unauthorized personnel to tamper with your equipment.")
				to_chat(user, "Law module applied.")

			if(istype(P, /obj/item/aiModule/purge))
				laws.clear_inherent_laws()
				to_chat(user, "Law module applied.")

			if(istype(P, /obj/item/aiModule/freeform))
				var/obj/item/aiModule/freeform/M = P
				laws.add_inherent_law(M.newFreeFormLaw)
				to_chat(user, "Added a freeform law.")

			if(istype(P, /obj/item/mmi))
				var/obj/item/mmi/M = P
				var/mob/living/carbon/brain/occupant = M.get_occupant()
				if(!occupant)
					to_chat(user, span_warning("Sticking an empty [P] into the frame would sort of defeat the purpose."))
					return
				if(occupant.stat == DEAD)
					to_chat(user, span_warning("Sticking a dead [P] into the frame would sort of defeat the purpose."))
					return

				if(jobban_isbanned(occupant, JOB_AI))
					to_chat(user, span_warning("This [P] does not seem to fit."))
					return

				if(occupant.mind)
					SSantag_job.clear_antag_roles(occupant.mind, 1)

				user.drop_item()
				P.loc = src
				brain = P
				to_chat(user, "Added [P].")
				icon_state = "3b"

/obj/structure/AIcore/wrench_act(mob/user, obj/item/tool)
	if(state != 0 && state != 1)
		return ITEM_INTERACT_BLOCKING
	if(state == 0)
		if(use_tool(user, tool, src, delay = 2 SECONDS, quality = TOOL_WRENCH, volume = 50))
			to_chat(user, span_notice("You wrench the frame into place."))
			anchored = TRUE
			state = 1
	else
		if(use_tool(user, tool, src, delay = 2 SECONDS, quality = TOOL_WRENCH, volume = 50))
			to_chat(user, span_notice("You unfasten the frame."))
			anchored = FALSE
			state = 0
	return ITEM_INTERACT_SUCCESS

/obj/structure/AIcore/welder_act(mob/user, obj/item/tool)
	if(state != 0)
		return ITEM_INTERACT_BLOCKING
	if(use_tool(user, tool, src, delay = 2 SECONDS, quality = TOOL_WELDER, volume = 50, amount = 0))
		to_chat(user, span_notice("You deconstruct the frame."))
		new /obj/item/stack/material/plasteel(loc, 4)
		qdel(src)
	return ITEM_INTERACT_SUCCESS

/obj/structure/AIcore/screwdriver_act(mob/user, obj/item/tool)
	switch(state)
		if(1)
			if(circuit)
				playsound(src, tool.usesound, 50, 1)
				to_chat(user, span_notice("You screw the circuit board into place."))
				state = 2
				icon_state = "2"
				return ITEM_INTERACT_SUCCESS
		if(2)
			if(circuit)
				playsound(src, tool.usesound, 50, 1)
				to_chat(user, span_notice("You unfasten the circuit board."))
				state = 1
				icon_state = "1"
				return ITEM_INTERACT_SUCCESS
		if(4)
			playsound(src, tool.usesound, 50, 1)
			to_chat(user, span_notice("You connect the monitor."))
			if(!brain)
				var/open_for_latejoin = tgui_alert(user, "Would you like this core to be open for latejoining AIs?", "Latejoin", list("Yes", "No")) == "Yes"
				var/obj/structure/AIcore/deactivated/D = new(loc)
				if(open_for_latejoin)
					GLOB.empty_playable_ai_cores += D
			else
				var/mob/living/silicon/ai/A = new /mob/living/silicon/ai(loc, FALSE, laws, brain)
				if(A) //if there's no brain, the mob is deleted and a structure/AIcore is created
					A.rename_self("ai", 1)
					for(var/datum/language/L in A.identity.languages)
						A.add_language(L.name)
			feedback_inc("cyborg_ais_created",1)
			qdel(src)
			return ITEM_INTERACT_SUCCESS
	return ITEM_INTERACT_BLOCKING

/obj/structure/AIcore/crowbar_act(mob/user, obj/item/tool)
	switch(state)
		if(1)
			if(circuit)
				playsound(src, tool.usesound, 50, 1)
				to_chat(user, span_notice("You remove the circuit board."))
				state = 1
				icon_state = "0"
				circuit.loc = loc
				circuit = null
				return ITEM_INTERACT_SUCCESS
		if(3)
			if(brain)
				playsound(src, tool.usesound, 50, 1)
				to_chat(user, span_notice("You remove the brain."))
				brain.loc = loc
				brain = null
				icon_state = "3"
				return ITEM_INTERACT_SUCCESS
		if(4)
			playsound(src, tool.usesound, 50, 1)
			to_chat(user, span_notice("You remove the glass panel."))
			state = 3
			if (brain)
				icon_state = "3b"
			else
				icon_state = "3"
			new /obj/item/stack/material/glass/reinforced( loc, 2 )
			return ITEM_INTERACT_SUCCESS
	return ITEM_INTERACT_BLOCKING

/obj/structure/AIcore/wirecutter_act(mob/user, obj/item/tool)
	if(state != 3)
		return ITEM_INTERACT_BLOCKING
	if (brain)
		to_chat(user, "Get that brain out of there first")
	else
		playsound(src, tool.usesound, 50, 1)
		to_chat(user, span_notice("You remove the cables."))
		state = 2
		icon_state = "2"
		new /obj/item/stack/cable_coil(loc, 5)
	return ITEM_INTERACT_SUCCESS

REGISTRY_MEMBERSHIP(/obj/structure/AIcore/deactivated, REGISTRY_AI_CORES_DEACTIVATED)

/obj/structure/AIcore/deactivated
	name = "inactive AI"
	icon = 'icons/mob/AI.dmi'
	icon_state = "ai-empty"
	anchored = TRUE
	state = 20//So it doesn't interact based on the above. Not really necessary.

/obj/structure/AIcore/deactivated/Destroy()
	if(src in GLOB.empty_playable_ai_cores)
		GLOB.empty_playable_ai_cores -= src
	return ..()

/obj/structure/AIcore/deactivated/proc/load_ai(mob/living/silicon/ai/transfer, obj/item/aicard/card, mob/user)

	if(!istype(transfer) || locate(/mob/living/silicon/ai) in src)
		return

	if(transfer.deployed_shell)
		transfer.disconnect_shell("Disconnected from remote shell due to core intelligence transfer.")
	transfer.aiRestorePowerRoutine = 0
	transfer.control_disabled = 0
	transfer.aiRadio.disabledAi = 0
	transfer.forceMove(get_turf(src))
	transfer.create_eyeobj()
	transfer.cancel_camera()
	to_chat(user, span_notice("Transfer successful:") + " [transfer.name] placed within stationary core.")
	to_chat(transfer, span_info("You have been transferred into a stationary core. Remote device connection restored."))

	if(card)
		card.clear()

	qdel(src)

/obj/structure/AIcore/deactivated/proc/check_malf(mob/living/silicon/ai/ai)
	if(!ai)
		return
	for (var/datum/mind/malfai in GLOB.malf.current_antagonists)
		if (ai.mind == malfai)
			return 1

/obj/structure/AIcore/deactivated/attackby(obj/item/W, mob/user)

	if(istype(W, /obj/item/aicard))
		var/obj/item/aicard/card = W
		var/mob/living/silicon/ai/transfer = locate() in card
		if(transfer)
			load_ai(transfer,card,user)
		else
			to_chat(user, span_danger("ERROR:") + " Unable to locate artificial intelligence.")
		return

	return ..()

/obj/structure/AIcore/deactivated/wrench_act(mob/user, obj/item/tool)
	if(anchored)
		user.visible_message(span_bold("\The [user]") + " starts to unbolt \the [src] from the plating...")
		if(!use_tool(user, tool, src, delay = 4 SECONDS, quality = TOOL_WRENCH, volume = 50))
			user.visible_message(span_bold("\The [user]") + " decides not to unbolt \the [src].")
			return ITEM_INTERACT_SUCCESS
		user.visible_message(span_bold("\The [user]") + " finishes unfastening \the [src]!")
		anchored = FALSE
		return ITEM_INTERACT_SUCCESS
	user.visible_message(span_bold("\The [user]") + " starts to bolt \the [src] to the plating...")
	if(!use_tool(user, tool, src, delay = 4 SECONDS, quality = TOOL_WRENCH, volume = 50))
		user.visible_message(span_bold("\The [user]") + " decides not to bolt \the [src].")
		return ITEM_INTERACT_SUCCESS
	user.visible_message(span_bold("\The [user]") + " finishes fastening down \the [src]!")
	anchored = TRUE
	return ITEM_INTERACT_SUCCESS

ADMIN_VERB(empty_ai_core_toggle_latejoin, R_ADMIN|R_SERVER|R_EVENT, "Toggle AI Core Latejoin", "Toggles the option to latejoin as AI core.", ADMIN_CATEGORY_SILICON)
	var/list/cores = list()
	for(var/obj/structure/AIcore/deactivated/current_ai_struct in REGISTRY_MEMBERS(REGISTRY_AI_CORES_DEACTIVATED))
		cores["[current_ai_struct] ([current_ai_struct.loc.loc])"] = current_ai_struct

	var/id = tgui_input_list(user, "Which core?", "Toggle AI Core Latejoin", cores)
	if(!id)
		return

	var/obj/structure/AIcore/deactivated/ai_struct = cores[id]
	if(!ai_struct)
		return

	if(ai_struct in GLOB.empty_playable_ai_cores)
		GLOB.empty_playable_ai_cores -= ai_struct
		to_chat(user, span_infoplain("\The [id] is now [span_red("not available")] for latejoining AIs."))
	else
		GLOB.empty_playable_ai_cores += ai_struct
		to_chat(user, span_infoplain("\The [id] is now [span_green("available")] for latejoining AIs."))
