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

DECLARE_INTERACTIONS(/obj/structure/AIcore, INTERACT_ITEM(null, PROC_REF(interaction_item)))

/// Old attackby.
/obj/structure/AIcore/proc/interaction_item(mob/user, obj/item/P, datum/interaction/interaction)

	switch(state)
		if(1)
			if(istype(P, /obj/item/circuitboard/aicore) && !circuit)
				playsound(src, 'sound/items/Deconstruct.ogg', 50, 1)
				to_chat(user, span_notice("You place the circuit board inside the frame."))
				icon_state = "1"
				circuit = P
				user.drop_item()
				P.forceMove(src)
		if(2)
			if(istype(P, /obj/item/stack/cable_coil))
				var/obj/item/stack/cable_coil/C = P
				if (C.get_amount() < 5)
					to_chat(user, span_warning("You need five coils of wire to add them to the frame."))
					return INTERACTION_HANDLED_PASS
				to_chat(user, span_notice("You start to add cables to the frame."))
				playsound(src, 'sound/items/Deconstruct.ogg', 50, 1)
				om_do_after(user, 2 SECONDS, target = src, receiver = src, on_done = PROC_REF(attackby_timed_done), done_args = list(user, C))
				return INTERACTION_HANDLED_PASS
		if(3)
			if(istype(P, /obj/item/stack/material) && P.get_material_name() == MAT_RGLASS)
				var/obj/item/stack/RG = P
				if (RG.get_amount() < 2)
					to_chat(user, span_warning("You need two sheets of glass to put in the glass panel."))
					return INTERACTION_HANDLED_PASS
				to_chat(user, span_notice("You start to put in the glass panel."))
				playsound(src, 'sound/items/Deconstruct.ogg', 50, 1)
				om_do_after(user, 2 SECONDS, target = src, receiver = src, on_done = PROC_REF(attackby_timed_done2), done_args = list(user, RG))

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
					return INTERACTION_HANDLED_PASS
				if(occupant.stat == DEAD)
					to_chat(user, span_warning("Sticking a dead [P] into the frame would sort of defeat the purpose."))
					return INTERACTION_HANDLED_PASS

				if(jobban_isbanned(occupant, JOB_AI))
					to_chat(user, span_warning("This [P] does not seem to fit."))
					return INTERACTION_HANDLED_PASS

				if(occupant.mind)
					GLOB.antag_service.clear_antag_roles(occupant.mind, 1)

				user.drop_item()
				P.forceMove(src)
				brain = P
				to_chat(user, "Added [P].")
				icon_state = "3b"
	return INTERACTION_HANDLED_PASS

/obj/structure/AIcore/proc/attackby_timed_done(mob/user, obj/item/stack/cable_coil/C)
	if(!(state == 2))
		return
	if (C.use(5))
		state = 3
		icon_state = "3"
		to_chat(user, span_notice("You add cables to the frame."))
/obj/structure/AIcore/proc/attackby_timed_done2(mob/user, obj/item/stack/RG)
	if(!(state == 3))
		return
	if(RG.use(2))
		to_chat(user, span_notice("You put in the glass panel."))
		state = 4
		icon_state = "4"

/obj/structure/AIcore/wrench_act(mob/user, obj/item/tool)
	if(state != 0 && state != 1)
		return ITEM_INTERACT_BLOCKING
	if(state == 0)
		use_tool(user, tool, src, delay = 2 SECONDS, quality = TOOL_WRENCH, volume = 50, receiver = src, on_done = PROC_REF(wrench_act_tool_done), done_args = list(user))
	else
		use_tool(user, tool, src, delay = 2 SECONDS, quality = TOOL_WRENCH, volume = 50, receiver = src, on_done = PROC_REF(wrench_act_tool_done2), done_args = list(user))
	return ITEM_INTERACT_SUCCESS

/obj/structure/AIcore/proc/wrench_act_tool_done(mob/user)
	to_chat(user, span_notice("You wrench the frame into place."))
	anchored = TRUE
	state = 1
/obj/structure/AIcore/proc/wrench_act_tool_done2(mob/user)
	to_chat(user, span_notice("You unfasten the frame."))
	anchored = FALSE
	state = 0

/obj/structure/AIcore/welder_act(mob/user, obj/item/tool)
	if(state != 0)
		return ITEM_INTERACT_BLOCKING
	use_tool(user, tool, src, delay = 2 SECONDS, quality = TOOL_WELDER, volume = 50, amount = 0, receiver = src, on_done = PROC_REF(welder_act_tool_done), done_args = list(user))
	return ITEM_INTERACT_SUCCESS

REGISTRY_MEMBERSHIP(/obj/structure/AIcore, REGISTRY_EMPTY_AI_CORES)
/obj/structure/AIcore/proc/welder_act_tool_done(mob/user)
	to_chat(user, span_notice("You deconstruct the frame."))
	replace_with(src, /obj/item/stack/material/plasteel, 4)

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
				var/obj/structure/AIcore/deactivated/D = new(loc)
				om_ask(user, /datum/om/prompt/confirm, TYPE_PROC_REF(/obj/structure/AIcore/deactivated, latejoin_answered), receiver = D, subject = D, title = "Latejoin", message = "Would you like this core to be open for latejoining AIs?")
			else
				var/mob/living/silicon/ai/A = new /mob/living/silicon/ai(loc, FALSE, laws, brain)
				if(A) //if there's no brain, the mob is deleted and a structure/AIcore is created
					A.rename_self("ai", 1)
					for(var/datum/language/L in A.identity().languages)
						A.add_language(L.name)
			feedback_inc("cyborg_ais_created",1)
			qdel(src)
			return ITEM_INTERACT_SUCCESS
	return ITEM_INTERACT_BLOCKING

/obj/structure/AIcore/deactivated/proc/latejoin_answered(datum/om/prompt/confirm/ask)
	registry_join(REGISTRY_EMPTY_AI_CORES, src)

/obj/structure/AIcore/crowbar_act(mob/user, obj/item/tool)
	switch(state)
		if(1)
			if(circuit)
				playsound(src, tool.usesound, 50, 1)
				to_chat(user, span_notice("You remove the circuit board."))
				state = 1
				icon_state = "0"
				circuit.forceMove(loc)
				circuit = null
				return ITEM_INTERACT_SUCCESS
		if(3)
			if(brain)
				playsound(src, tool.usesound, 50, 1)
				to_chat(user, span_notice("You remove the brain."))
				brain.forceMove(loc)
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

/obj/structure/AIcore/deactivated/proc/load_ai(mob/living/silicon/ai/transfer, obj/item/aicard/card, mob/user)

	if(!istype(transfer) || locate_within(src, /mob/living/silicon/ai))
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

EXTEND_INTERACTIONS(/obj/structure/AIcore/deactivated, INTERACT_ITEM(null, PROC_REF(deactivated_interaction_item)))

/// Old attackby.
/obj/structure/AIcore/deactivated/proc/deactivated_interaction_item(mob/user, obj/item/W, datum/interaction/interaction)

	if(istype(W, /obj/item/aicard))
		var/obj/item/aicard/card = W
		var/mob/living/silicon/ai/transfer = locate_within(card, /mob/living/silicon/ai)
		if(transfer)
			load_ai(transfer,card,user)
		else
			to_chat(user, span_danger("ERROR:") + " Unable to locate artificial intelligence.")
		return INTERACTION_HANDLED_PASS

	return FALSE

/obj/structure/AIcore/deactivated/wrench_act(mob/user, obj/item/tool)
	if(anchored)
		user.visible_message(span_bold("\The [user]") + " starts to unbolt \the [src] from the plating...")
		use_tool(user, tool, src, delay = 4 SECONDS, quality = TOOL_WRENCH, volume = 50, receiver = src, on_done = PROC_REF(unbolted), done_args = list(user), on_fail = PROC_REF(unbolt_abandoned), fail_args = list(user))
		return ITEM_INTERACT_SUCCESS
	user.visible_message(span_bold("\The [user]") + " starts to bolt \the [src] to the plating...")
	use_tool(user, tool, src, delay = 4 SECONDS, quality = TOOL_WRENCH, volume = 50, receiver = src, on_done = PROC_REF(wrench_act_tool_done3), done_args = list(user), on_fail = PROC_REF(wrench_act_tool_failed3), fail_args = list(user))
	return ITEM_INTERACT_SUCCESS

/obj/structure/AIcore/deactivated/proc/wrench_act_tool_done3(mob/user)
	user.visible_message(span_bold("\The [user]") + " finishes fastening down \the [src]!")
	anchored = TRUE
	return ITEM_INTERACT_SUCCESS

/obj/structure/AIcore/deactivated/proc/wrench_act_tool_failed3(mob/user)
	user.visible_message(span_bold("\The [user]") + " decides not to bolt \the [src].")
	return ITEM_INTERACT_SUCCESS

ADMIN_VERB(empty_ai_core_toggle_latejoin, R_ADMIN|R_SERVER|R_EVENT, "Toggle AI Core Latejoin", "Toggles the option to latejoin as AI core.", ADMIN_CATEGORY_SILICON)
	var/list/cores = list()
	for(var/obj/structure/AIcore/deactivated/current_ai_struct in REGISTRY_MEMBERS(REGISTRY_AI_CORES_DEACTIVATED))
		cores["[current_ai_struct] ([current_ai_struct.loc.loc])"] = current_ai_struct

	om_ask(user, /datum/om/prompt/choice, TYPE_PROC_REF(/client, empty_ai_core_latejoin_chosen), receiver = user, choices = cores, title = "Toggle AI Core Latejoin", message = "Which core?", requires = PROMPT_ADMIN(R_ADMIN|R_SERVER|R_EVENT))

/client/proc/empty_ai_core_latejoin_chosen(datum/om/prompt/choice/ask)
	var/list/cores = ask.choices
	var/id = ask.choice
	var/mob/user = mob

	var/obj/structure/AIcore/deactivated/ai_struct = cores[id]
	if(!ai_struct)
		return

	if(ai_struct in REGISTRY_MEMBERS(REGISTRY_EMPTY_AI_CORES))
		registry_leave(REGISTRY_EMPTY_AI_CORES, ai_struct)
		to_chat(user, span_infoplain("\The [id] is now [span_red("not available")] for latejoining AIs."))
	else
		registry_join(REGISTRY_EMPTY_AI_CORES, ai_struct)
		to_chat(user, span_infoplain("\The [id] is now [span_green("available")] for latejoining AIs."))

/obj/structure/AIcore/deactivated/proc/unbolted(mob/user)
	user.visible_message(span_bold("\The [user]") + " finishes unfastening \the [src]!")
	anchored = FALSE

/obj/structure/AIcore/deactivated/proc/unbolt_abandoned(mob/user)
	user?.visible_message(span_bold("\The [user]") + " decides not to unbolt \the [src].")

// laws are handed to the AI built from this core, so they aren't owned here.
DECLARE_REF(/obj/structure/AIcore, "laws", HELD, null)
DECLARE_REF(/obj/structure/AIcore, "circuit", HELD, null)
DECLARE_REF(/obj/structure/AIcore, "brain", HELD, null)
