/*
	Integrated circuits are essentially modular machines.  Each circuit has a specific function, and combining them inside Electronic Assemblies allows
a creative player the means to solve many problems.  Circuits are held inside an electronic assembly, and are wired using special tools.
*/

/obj/item/integrated_circuit/examine(mob/user)
	. = ..()
	. += external_examine(user)
	tgui_interact(user)

// This should be used when someone is examining while the case is opened.
/obj/item/integrated_circuit/proc/internal_examine(mob/user)
	. = list()
	. += "This board has [inputs.len] input pin\s, [outputs.len] output pin\s and [activators.len] activation pin\s."
	for(var/datum/integrated_io/I in inputs)
		if(LAZYLEN(I.linked))
			. += "The '[I]' is connected to [I.get_linked_to_desc()]."
	for(var/datum/integrated_io/O in outputs)
		if(LAZYLEN(O.linked))
			. += "The '[O]' is connected to [O.get_linked_to_desc()]."
	for(var/datum/integrated_io/activate/A in activators)
		if(LAZYLEN(A.linked))
			. += "The '[A]' is connected to [A.get_linked_to_desc()]."
	. += any_examine(user)
	tgui_interact(user)

// This should be used when someone is examining from an 'outside' perspective, e.g. reading a screen or LED.
/obj/item/integrated_circuit/proc/external_examine(mob/user)
	return any_examine(user)

/obj/item/integrated_circuit/proc/any_examine(mob/user)
	return

// ALLOW(init/FRAMEWORK): the circuit base builds its pins from the defaults its type declares
/obj/item/integrated_circuit/Initialize(mapload)
	. = ..()
	displayed_name = name
	if(!size) size = w_class
	if(size == -1) size = 0
	setup_io("inputs", /datum/integrated_io, inputs_default)
	setup_io("outputs", /datum/integrated_io, outputs_default)
	setup_io("activators", /datum/integrated_io/activate)

/obj/item/integrated_circuit/proc/on_data_written() //Override this for special behaviour when new data gets pushed to the circuit.
	return



/// A pulse scrambles every pin.
/obj/item/integrated_circuit/proc/circuit_emp_scramble(datum/act/A)
	for(var/datum/integrated_io/io in inputs + outputs + activators)
		io.scramble()

/obj/item/integrated_circuit/proc/check_interactivity(mob/user)
	return tgui_status(user, GLOB.tgui_physical_state) == STATUS_INTERACTIVE

EXTEND_INTERACTIONS(/obj/item/integrated_circuit, INTERACT_VERB("Rename Circuit", PROC_REF(integrated_circuit_verb_rename), REQ_IN_INVENTORY))

/// Old Rename Circuit verb: Rename your circuit, useful to stay organized.
/obj/item/integrated_circuit/proc/integrated_circuit_verb_rename(mob/user, obj/item/held, datum/interaction/interaction)
	var/mob/M = user
	if(!check_interactivity(M))
		return

	if(!ismob(M) || QDELETED(M))
		return
	open_request(src, /datum/prompt/text/electronics_rename, PROC_REF(rename_entered), answerer = M, captured_item = held, captured_interaction = interaction, item_expected = !isnull(held), interaction_expected = !isnull(interaction), question = "What do you want to name the circuit?", default = name)

/obj/item/integrated_circuit/proc/rename_entered(datum/act/request/A)
	var/datum/prompt/text/electronics_rename/request = A.request
	if(request.captures_gone())
		return
	if(!A.answer)
		if(request.outcome == REQ_CANCELLED && !isnull(request.value))
			SStgui.update_uis(src)
		return
	apply_rename(A)
	SStgui.update_uis(src)

/obj/item/integrated_circuit/proc/apply_rename(datum/act/request/A)
	var/mob/M = A.request.answerer
	if(!check_interactivity(M))
		return
	var/_answer_k80 = A.answer.value
	var/input = sanitizeSafe(_answer_k80, MAX_NAME_LEN)
	if(src && input && assembly().check_interactivity(M))
		to_chat(M, span_notice("The circuit '[src.name]' is now labeled '[input]'."))
		displayed_name = input

/datum/prompt/text/electronics_rename
	title = "Rename"
	timeout = 0
	max_len = MAX_NAME_LEN
	name_text = TRUE
	encode = FALSE
	multiline = FALSE
	var/obj/item/captured_item
	var/datum/interaction/captured_interaction
	var/item_expected = FALSE
	var/interaction_expected = FALSE

CAPABILITIES(/datum/prompt/text/electronics_rename)
	ref_one(nameof(captured_item), /obj/item)
	ref_one(nameof(captured_interaction), /datum/interaction)

/datum/prompt/text/electronics_rename/prepare(datum/act/A)
	. = ..()
	var/obj/item/item = captured_item
	var/datum/interaction/interaction = captured_interaction
	rel_clear(src, nameof(captured_item))
	rel_clear(src, nameof(captured_interaction))
	rel_set(src, nameof(captured_item), item)
	rel_set(src, nameof(captured_interaction), interaction)

/datum/prompt/text/electronics_rename/proc/captures_gone()
	return QDELETED(answerer) || (item_expected && QDELETED(captured_item)) || (interaction_expected && QDELETED(captured_interaction))

/datum/prompt/text/electronics_rename/recheck_extra()
	. = ..()
	if(.)
		return
	if(captures_gone())
		return "gone"
	return null

/obj/item/integrated_circuit/tgui_host(mob/user)
	if(istype(loc, /obj/item/electronic_assembly))
		return loc.tgui_host()
	return ..()

/obj/item/integrated_circuit/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["name"] = name
	data["desc"] = desc
	data["displayed_name"] = displayed_name
	data["removable"] = removable
	data["complexity"] = complexity
	data["power_draw_idle"] = power_draw_idle
	data["power_draw_per_use"] = power_draw_per_use
	data["extended_desc"] = extended_desc
	var/list/merged_1 = ui_data_obj_item_integrated_circuit(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/item/integrated_circuit's window data.
/obj/item/integrated_circuit/proc/ui_data_obj_item_integrated_circuit(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	data["ref"] = REF(src)


	var/list/inputs_list = list()
	var/list/outputs_list = list()
	var/list/activators_list = list()
	for(var/datum/integrated_io/io in inputs)
		UNTYPED_LIST_ADD(inputs_list, tgui_pin_data(io))

	for(var/datum/integrated_io/io in outputs)
		UNTYPED_LIST_ADD(outputs_list, tgui_pin_data(io))

	for(var/datum/integrated_io/io in activators)
		UNTYPED_LIST_ADD(activators_list, tgui_pin_data(io))

	data["inputs"] = inputs_list
	data["outputs"] = outputs_list
	data["activators"] = activators_list

	return data

/obj/item/integrated_circuit/proc/tgui_pin_data(datum/integrated_io/io)
	if(!istype(io))
		return list()
	var/list/pindata = list()
	pindata["type"] = io.display_pin_type()
	pindata["name"] = io.name
	pindata["data"] = io.display_data(io.data)
	pindata["rawdata"] = io.data
	pindata["ref"] = REF(io)
	var/list/linked_list = list()
	for(var/datum/integrated_io/linked in io.linked)
		UNTYPED_LIST_ADD(linked_list, list(
			"ref" = REF(linked),
			"name" = linked.name,
			"holder_ref" = REF(linked.holder()),
			"holder_name" = linked.holder().displayed_name,
		))
	pindata["linked"] = linked_list
	return pindata

/// Every pin of this circuit, for the UI's pin refs.
/obj/item/integrated_circuit/proc/all_pins()
	return inputs + outputs + activators

/// Every pin the circuit's pins are wired to, for the UI's link refs.
/obj/item/integrated_circuit/proc/all_linked_pins()
	. = list()
	for(var/datum/integrated_io/pin as anything in all_pins())
		. |= pin.linked

/obj/item/integrated_circuit/proc/ui_act_rename(datum/act/op/A)
	var/mob/user = A.actor
	. = TRUE
	integrated_circuit_verb_rename(user)
	return

/obj/item/integrated_circuit/proc/ui_act_wire(datum/act/op/A, link, pin_arg)
	var/mob/user = A.actor
	var/action = A.window_action()
	if(!isnull(link) && !(link in all_linked_pins()))
		return FALSE
	if(!isnull(pin_arg) && !(pin_arg in all_pins()))
		return FALSE
	. = TRUE
	var/datum/integrated_io/pin = pin_arg
	var/datum/integrated_io/linked = link
	var/obj/item/held_item = user.get_active_hand()
	if(!pin || !(linked in pin.linked))
		linked = null
	var/obj/item/multitool/M = held_item?.get_multitool()
	if(M && allow_multitool)
		switch(action)
			if("pin_name")
				M.wire(pin, user)
			if("pin_data")
				var/datum/integrated_io/io = pin
				io.ask_for_pin_data(user, held_item) // The pins themselves will determine how to ask for data, and will validate the data.
			if("pin_unwire")
				M.unwire(pin, linked, user)

	else if(istype(held_item, /obj/item/integrated_electronics/wirer))
		var/obj/item/integrated_electronics/wirer/wirer = held_item
		if(linked)
			wirer.wire(linked, user)
		else if(pin)
			wirer.wire(pin, user)

	else if(istype(held_item, /obj/item/integrated_electronics/debugger))
		var/obj/item/integrated_electronics/debugger/debugger = held_item
		if(pin)
			debugger.write_data(pin, user)
	else
		to_chat(user, span_warning("You can't do a whole lot without the proper tools."))
	return

/obj/item/integrated_circuit/proc/ui_act_scan(datum/act/op/A)
	var/mob/user = A.actor
	. = TRUE
	var/obj/item/held_item = user.get_active_hand()
	if(istype(held_item, /obj/item/integrated_electronics/debugger))
		var/obj/item/integrated_electronics/debugger/D = held_item
		if(D.accepting_refs)
			D.afterattack(src, user, TRUE)
		else
			to_chat(user, span_warning("The Debugger's 'ref scanner' needs to be on."))
	else
		to_chat(user, span_warning("You need a multitool/debugger set to 'ref' mode to do that."))
	return

/obj/item/integrated_circuit/proc/ui_act_examine(datum/act/op/A, ref)
	var/mob/user = A.actor
	var/datum/tgui/ui = A.window_ui() || SStgui.get_open_ui(user, src) // the window the button was pressed in
	. = TRUE
	var/obj/item/integrated_circuit/examined = ref
	if(istype(examined) && (examined.loc == loc))
		if(ui.parent_ui())
			examined.tgui_interact(user, null, ui.parent_ui())
		else
			examined.tgui_interact(user)
	return FALSE

/obj/item/integrated_circuit/proc/ui_act_remove(datum/act/op/A)
	var/mob/user = A.actor
	. = TRUE
	remove(user)
	return

/obj/item/integrated_circuit/proc/remove(mob/user)
	var/obj/item/electronic_assembly/A = assembly()
	if(!A)
		to_chat(user, span_warning("This circuit is not in an assembly!"))
		return
	if(!removable)
		to_chat(user, span_warning("\The [src] seems to be permanently attached to the case."))
		return
	var/obj/item/electronic_assembly/ea = loc

	power_fail()
	disconnect_all()
	var/turf/T = get_turf(src)
	forceMove(T)
	rel_clear(src, nameof(assembly))
	play_sfx(T, SFX_ITEMS_CROWBAR)
	to_chat(user, span_notice("You pop \the [src] out of the case, and slide it out."))

	if(istype(ea))
		ea.tgui_interact(user)

/obj/item/integrated_circuit/proc/push_data()
	for(var/datum/integrated_io/O in outputs)
		O.push_data()

/obj/item/integrated_circuit/proc/pull_data()
	for(var/datum/integrated_io/I in inputs)
		I.push_data()

/obj/item/integrated_circuit/proc/draw_idle_power()
	if(assembly())
		return assembly().draw_power(power_draw_idle)

// Override this for special behaviour when there's no power left.
/obj/item/integrated_circuit/proc/power_fail()
	return

// Returns true if there's enough power to work().
/obj/item/integrated_circuit/proc/check_power()
	if(!assembly())
		return FALSE // Not in an assembly, therefore no power.
	if(assembly().draw_power(power_draw_per_use))
		return TRUE // Battery has enough.
	return FALSE // Not enough power.

/obj/item/integrated_circuit/proc/check_then_do_work(ignore_power = FALSE, work_left = IC_MAX_PULSE_CIRCUITS)
	if(!COOLDOWN_FINISHED(src, next_use)) 	// All intergrated circuits have an internal cooldown, to protect from spam.
		return
	// Per-propagation work ceiling: a single synchronous pulse can fan out across
	// the reachable circuit graph faster than the 1s per-circuit cooldown gates
	// it. Bail (with feedback) before a pathological wide assembly stalls the
	// tick. Normal assemblies never approach IC_MAX_PULSE_CIRCUITS.
	if(work_left <= 0)
		if(assembly())
			assembly().visible_message(span_warning("\The [assembly()] buzzes and overheats, its circuits unable to keep up!"))
		return
	if(power_draw_per_use && !ignore_power)
		if(!check_power())
			power_fail()
			return
	COOLDOWN_START(src, next_use, cooldown_per_use)
	// Stash the remaining budget so activate_pin() — called from inside the many
	// do_work() overrides without threading an arg — can forward it downstream.
	ic_work_budget = work_left - 1
	do_work()
	ic_work_budget = IC_MAX_PULSE_CIRCUITS

/obj/item/integrated_circuit/proc/do_work()
	return

/obj/item/integrated_circuit/proc/disconnect_all()
	for(var/datum/integrated_io/I in inputs)
		I.disconnect()
	for(var/datum/integrated_io/O in outputs)
		O.disconnect()
	for(var/datum/integrated_io/activate/A in activators)
		A.disconnect()

/obj/item/integrated_circuit/proc/on_anchored()
	return

/obj/item/integrated_circuit/proc/on_unanchored()
	return
