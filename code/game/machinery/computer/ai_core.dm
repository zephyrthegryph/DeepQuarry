TRACKED(/obj/structure/AIcore, state)
MSG_DEF(ai_core/unbolt_start, null, "<span class='bold'>%U%</span> starts to unbolt %T% from the plating...")
MSG_DEF(ai_core/bolt_start, null, "<span class='bold'>%U%</span> starts to bolt %T% to the plating...")
MSG_DEF_SELF(ai_core/board_unfastened, "the circuit board must be fastened before wiring")
MSG_DEF_SELF(ai_core/not_wired, "the core must be wired before installing its panel")
MSG_DEF_SELF(ai_core/reinforced_glass, "needs reinforced glass")
MSG_DEF_SELF(ai_core/wiring_start, "You start to add cables to the frame.")
MSG_DEF_SELF(ai_core/glass_start, "You start to put in the glass panel.")
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

CAPABILITIES(/obj/structure/AIcore)
	// 0 a loose frame, 1 bolted down (the board goes in), 2 the board screwed in, 3 wired (laws and the brain go in), 4 the glass panel on; the
	// screwdriver on a paneled core makes the AI
	stages(nameof(state),
		stage_step(0, 1, tool(TOOL_WRENCH), label("Anchor frame"), starts(PROC_REF(construction_tool_started)), wait(PROC_REF(frame_wrench_duration)), then(PROC_REF(frame_anchored)), key = "anchor"),
		stage_step(1, 0, tool(TOOL_WRENCH), label("Unfasten frame"), starts(PROC_REF(construction_tool_started)), wait(PROC_REF(frame_wrench_duration)), then(PROC_REF(frame_unanchored)), key = "unanchor"),
		stage_step(1, 2, tool(TOOL_SCREWDRIVER), label("Screw the board in"), when(PROC_REF(has_circuit)), wait(0), then(PROC_REF(board_fastened))),
		stage_step(2, 1, tool(TOOL_SCREWDRIVER), label("Unfasten the board"), when(PROC_REF(has_circuit)), wait(0), then(PROC_REF(board_unfastened))),
		stage_step(2, 3, stack(/obj/item/stack/cable_coil, 5), begins(MSG(ai_core/wiring_start)), plays(SFX_ITEMS_DECONSTRUCT, at_start = TRUE), wait(2 SECONDS), then(PROC_REF(attackby_timed_done)), key = "add_cables"),
		stage_step(3, 2, tool(TOOL_WIRECUTTER), label("Remove the cables"), needs(req(PROC_REF(brain_out_refusal))), wait(0), then(PROC_REF(cables_cut))),
		stage_step(3, 4, stack(/obj/item/stack/material, 2), when(req(PROC_REF(reinforced_panel))), needs(req(PROC_REF(reinforced_panel))), begins(MSG(ai_core/glass_start)), plays(SFX_ITEMS_DECONSTRUCT, at_start = TRUE), wait(2 SECONDS), then(PROC_REF(attackby_timed_done2)), key = "add_panel"),
		stage_step(4, 3, tool(TOOL_CROWBAR), label("Remove the glass panel"), wait(0), then(PROC_REF(panel_removed))))
	op("dismantle", lit_welder(fuel = 0), label("Dismantle frame"), starts(PROC_REF(construction_welder_started)), when(req_stage(nameof(state), 0)), wait(PROC_REF(frame_weld_duration)), then(PROC_REF(welder_act_tool_done)))
	op("remove_board", tool(TOOL_CROWBAR), label("Remove the circuit board"), when(req_stage(nameof(state), 1)), when(PROC_REF(has_circuit)), wait(0), then(PROC_REF(board_removed)))
	op("remove_brain", tool(TOOL_CROWBAR), label("Remove the brain"), when(req_stage(nameof(state), 3)), when(PROC_REF(has_brain)), wait(0), then(PROC_REF(brain_removed)))
	op("connect_monitor", tool(TOOL_SCREWDRIVER), label("Connect the monitor"), when(req_stage(nameof(state), 4)), wait(0), then(PROC_REF(monitor_connected)))
	op("ai_core_install", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_item)))
	owns_one(nameof(laws), /datum/ai_laws, starts = PROC_REF(make_laws))

/// A map-placed core starts with the map's default law set (owns_one(starts =)); a built one gets its laws from its board.
/obj/structure/AIcore/proc/make_laws(current, mapload)
	if(mapload)
		return new using_map.default_law_type



/// Old attackby.
/obj/structure/AIcore/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/P = A.held

	switch(state)
		if(1)
			if(istype(P, /obj/item/circuitboard/aicore) && !circuit)
				play_sfx(src, SFX_ITEMS_DECONSTRUCT)
				to_chat(user, span_notice("You place the circuit board inside the frame."))
				set_icon_state("1")
				move_into(src, nameof(src.circuit), P, user)
		if(3)

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
					return OP_PASS
				if(occupant.stat == DEAD)
					to_chat(user, span_warning("Sticking a dead [P] into the frame would sort of defeat the purpose."))
					return OP_PASS

				if(jobban_isbanned(occupant, JOB_AI))
					to_chat(user, span_warning("This [P] does not seem to fit."))
					return OP_PASS

				if(occupant.mind)
					SSantag.clear_antag_roles(occupant.mind, 1)

				if(!move_into(src, nameof(src.brain), P, user))
					return OP_PASS
				to_chat(user, "Added [P].")
				set_icon_state("3b")
	return OP_PASS

/obj/structure/AIcore/proc/reinforced_panel(datum/act/op/A)
	return (read_once(A.held.get_material_name()) == MAT_RGLASS) ? null : MSG(ai_core/reinforced_glass)

/obj/structure/AIcore/proc/attackby_timed_done(datum/act/op/A)
	set_icon_state("3")
	to_chat(A.actor, span_notice("You add cables to the frame."))
	return OP_OK

/obj/structure/AIcore/proc/attackby_timed_done2(datum/act/op/A)
	to_chat(A.actor, span_notice("You put in the glass panel."))
	set_icon_state("4")
	return OP_OK

/obj/structure/AIcore/proc/frame_wrench_duration(datum/act/op/A)
	var/obj/item/tool = A.held_provider()
	return 2 SECONDS * tooling_of(tool).speed * tool_skill_factor(A.actor, TOOL_WRENCH)

/obj/structure/AIcore/proc/frame_weld_duration(datum/act/op/A)
	var/obj/item/tool = A.held_provider()
	return 2 SECONDS * tooling_of(tool).speed * tool_skill_factor(A.actor, TOOL_WELDER)

/obj/structure/AIcore/deactivated/proc/core_wrench_duration(datum/act/op/A)
	var/obj/item/tool = A.held_provider()
	return 4 SECONDS * tooling_of(tool).speed * tool_skill_factor(A.actor, TOOL_WRENCH)
/obj/structure/AIcore/proc/construction_welder_started(datum/act/op/A)
	var/obj/item/tool = A.held_provider()
	var/obj/item/weldingtool/welder = tool.get_welder()
	welder.eyecheck(A.actor)
	construction_tool_started(A)
/obj/structure/AIcore/proc/construction_tool_started(datum/act/op/A)
	var/obj/item/tool = A.held_provider()
	if(sounds_of(tool).use)
		play_sfx(src, sounds_of(tool).use, volume = 50, vary = TRUE)
/obj/structure/AIcore/proc/frame_anchored(datum/act/op/A)
	to_chat(A.actor, span_notice("You wrench the frame into place."))
	set_anchored(TRUE)
	return OP_OK

/obj/structure/AIcore/proc/frame_unanchored(datum/act/op/A)
	to_chat(A.actor, span_notice("You unfasten the frame."))
	set_anchored(FALSE)
	return OP_OK

/// The frame holds a circuit board (the board steps and its removal).
/obj/structure/AIcore/proc/has_circuit(datum/act/op/A)
	return !!read_once(circuit)

/obj/structure/AIcore/proc/has_brain(datum/act/op/A)
	return !!read_once(brain)

/obj/structure/AIcore/proc/brain_out_refusal(datum/act/op/A)
	return read_once(brain) ? "get that brain out of there first" : null

/obj/structure/AIcore/proc/board_fastened(datum/act/op/A)
	var/obj/item/tool = A.held
	playsound(src, sounds_of(tool).use, 50, 1)
	to_chat(A.actor, span_notice("You screw the circuit board into place."))
	set_icon_state("2")
	return OP_OK

/obj/structure/AIcore/proc/board_unfastened(datum/act/op/A)
	var/obj/item/tool = A.held
	playsound(src, sounds_of(tool).use, 50, 1)
	to_chat(A.actor, span_notice("You unfasten the circuit board."))
	set_icon_state("1")
	return OP_OK

/obj/structure/AIcore/proc/board_removed(datum/act/op/A)
	var/obj/item/tool = A.held
	playsound(src, sounds_of(tool).use, 50, 1)
	to_chat(A.actor, span_notice("You remove the circuit board."))
	set_icon_state("0")
	circuit.forceMove(loc)
	rel_take(src, nameof(circuit))
	return OP_OK

/obj/structure/AIcore/proc/brain_removed(datum/act/op/A)
	var/obj/item/tool = A.held
	playsound(src, sounds_of(tool).use, 50, 1)
	to_chat(A.actor, span_notice("You remove the brain."))
	brain.forceMove(loc)
	rel_take(src, nameof(brain))
	set_icon_state("3")
	return OP_OK

/obj/structure/AIcore/proc/panel_removed(datum/act/op/A)
	var/obj/item/tool = A.held
	playsound(src, sounds_of(tool).use, 50, 1)
	to_chat(A.actor, span_notice("You remove the glass panel."))
	set_icon_state(brain ? "3b" : "3")
	new /obj/item/stack/material/glass/reinforced(loc, 2)
	return OP_OK

/obj/structure/AIcore/proc/cables_cut(datum/act/op/A)
	var/obj/item/tool = A.held
	playsound(src, sounds_of(tool).use, 50, 1)
	to_chat(A.actor, span_notice("You remove the cables."))
	set_icon_state("2")
	new /obj/item/stack/cable_coil(loc, 5)
	return OP_OK
REGISTRY_MEMBERSHIP(/obj/structure/AIcore, REGISTRY_EMPTY_AI_CORES)
/obj/structure/AIcore/proc/welder_act_tool_done(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_notice("You deconstruct the frame."))
	replace_with(src, /obj/item/stack/material/plasteel, 4)

/// The paneled core's monitor is connected: the brain becomes the AI (or, with none, an empty core waits for one).
/obj/structure/AIcore/proc/monitor_connected(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	playsound(src, sounds_of(tool).use, 50, 1)
	to_chat(user, span_notice("You connect the monitor."))
	if(!brain)
		var/obj/structure/AIcore/deactivated/D = new(loc)
		perform_op(user, D, "latejoin_offer", origin = ORIGIN_SYSTEM)
	else
		var/datum/ai_laws/handed_laws = rel_take(src, nameof(laws)) // the new AI adopts them
		var/mob/living/silicon/ai/new_ai = new /mob/living/silicon/ai(loc, FALSE, handed_laws, brain)
		if(new_ai) //if there's no brain, the mob is deleted and a structure/AIcore is created
			new_ai.rename_self("ai", 1)
			for(var/datum/language/L in new_ai.identity().languages)
				new_ai.add_language(L.name)
	feedback_inc("cyborg_ais_created",1)
	destroyed(src, user, "deconstructed")
	return OP_OK

/obj/structure/AIcore/deactivated/proc/latejoin_answered(datum/act/op/A)
	if(!A.step_value("latejoin"))
		return
	registry_join(REGISTRY_EMPTY_AI_CORES, src)

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
	transfer.set_aiRestorePowerRoutine(0)
	transfer.control_disabled = 0
	transfer.aiRadio.disabledAi = 0
	transfer.forceMove(get_turf(src))
	transfer.create_eyeobj()
	transfer.cancel_camera()
	to_chat(user, span_notice("Transfer successful:") + " [transfer.name] placed within stationary core.")
	to_chat(transfer, span_info("You have been transferred into a stationary core. Remote device connection restored."))

	if(card)
		card.clear()

	spent(src, user)

/obj/structure/AIcore/deactivated/proc/check_malf(mob/living/silicon/ai/ai)
	if(!ai)
		return
	for (var/datum/mind/malfai in GLOB.malf.current_antagonists)
		if (ai.mind == malfai)
			return 1

CAPABILITIES(/obj/structure/AIcore/deactivated)
	without("anchor")
	without("unanchor")
	op("unbolt", tool(TOOL_WRENCH), label("Unbolt core"), starts(PROC_REF(construction_tool_started)), when(req_is(nameof(anchored), TRUE)), begins(MSG(ai_core/unbolt_start)), wait(PROC_REF(core_wrench_duration)), then(PROC_REF(unbolted)), on_interrupt(PROC_REF(unbolt_abandoned)))
	op("bolt", tool(TOOL_WRENCH), label("Bolt core"), starts(PROC_REF(construction_tool_started)), when(req_is(nameof(anchored), FALSE)), begins(MSG(ai_core/bolt_start)), wait(PROC_REF(core_wrench_duration)), then(PROC_REF(wrench_act_tool_done3)), on_interrupt(PROC_REF(wrench_act_tool_failed3)))
	op("latejoin_offer", ai(), asks(/datum/prompt/yes_no, fields = list("title" = "Latejoin", "question" = "Would you like this core to be open for latejoining AIs?", "timeout" = 0), step = "latejoin"), then(PROC_REF(latejoin_answered)))
	op("deactivated_interaction_item", item(/obj/item), then(PROC_REF(deactivated_interaction_item)))

/// Old attackby.
/obj/structure/AIcore/deactivated/proc/deactivated_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held

	if(istype(W, /obj/item/aicard))
		var/obj/item/aicard/card = W
		var/mob/living/silicon/ai/transfer = locate_within(card, /mob/living/silicon/ai)
		if(transfer)
			load_ai(transfer,card,user)
		else
			to_chat(user, span_danger("ERROR:") + " Unable to locate artificial intelligence.")
		return OP_PASS

	return OP_DECLINE

/obj/structure/AIcore/deactivated/proc/wrench_act_tool_done3(datum/act/op/A)
	var/mob/user = A.actor
	act_message(user, src, others = span_bold("%U%") + " finishes fastening down %T%!")
	set_anchored(TRUE)
	return ITEM_INTERACT_SUCCESS

/obj/structure/AIcore/deactivated/proc/wrench_act_tool_failed3(datum/act/op/A)
	var/mob/user = A.actor
	act_message(user, src, others = span_bold("%U%") + " decides not to bolt %T%.")
	return ITEM_INTERACT_SUCCESS

/// The deactivated cores by the name the admin's question lists them under.
/proc/empty_ai_core_choices()
	var/list/cores = list()
	for(var/obj/structure/AIcore/deactivated/current_ai_struct in REGISTRY_MEMBERS(REGISTRY_AI_CORES_DEACTIVATED))
		cores["[current_ai_struct] ([current_ai_struct.loc.loc])"] = current_ai_struct
	return cores

ADMIN_VERB(empty_ai_core_toggle_latejoin, R_ADMIN|R_SERVER|R_EVENT, "Toggle AI Core Latejoin", "Toggles the option to latejoin as AI core.", ADMIN_CATEGORY_SILICON)
	perform_op(user.mob, user.admin_datum(), "empty_ai_core_latejoin", origin = ORIGIN_SYSTEM)

/// The admin still holds the rights to do this when the answer arrives.
/datum/admins/proc/empty_ai_core_latejoin_valid(datum/act/op/A)
	return (read_once(A.actor?.client) == read_once(owner()) && check_rights_for(read_once(owner()), R_ADMIN|R_SERVER|R_EVENT)) ? null : "administrator rights required"

/datum/admins/proc/empty_ai_core_latejoin_chosen(datum/act/op/A)
	var/id = A.step_value("core")
	var/mob/user = A.actor

	var/obj/structure/AIcore/deactivated/ai_struct = empty_ai_core_choices()[id]
	if(!ai_struct)
		return

	if(ai_struct in REGISTRY_MEMBERS(REGISTRY_EMPTY_AI_CORES))
		registry_leave(REGISTRY_EMPTY_AI_CORES, ai_struct)
		to_chat(user, span_infoplain("\The [id] is now [span_red("not available")] for latejoining AIs."))
	else
		registry_join(REGISTRY_EMPTY_AI_CORES, ai_struct)
		to_chat(user, span_infoplain("\The [id] is now [span_green("available")] for latejoining AIs."))

/obj/structure/AIcore/deactivated/proc/unbolted(datum/act/op/A)
	var/mob/user = A.actor
	act_message(user, src, others = span_bold("%U%") + " finishes unfastening %T%!")
	set_anchored(FALSE)

/obj/structure/AIcore/deactivated/proc/unbolt_abandoned(datum/act/op/A)
	var/mob/user = A.actor
	act_message(user, src, others = span_bold("%U%") + " decides not to unbolt %T%.")

// The core owns its laws until it builds an AI, which adopts them (own_take() in the build step).
/obj/structure/AIcore/ownership()
	. = ..()
	. += owns(nameof(circuit), policy = OWN_CONTAINED)
	. += owns(nameof(brain), policy = OWN_CONTAINED)

/datum/admins/proc/empty_ai_core_options(datum/act/op/A)
	return assoc_to_keys(empty_ai_core_choices())
