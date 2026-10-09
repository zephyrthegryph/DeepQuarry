// Here is where the base definition lives.
// Specific subtypes are in their own folder.

/obj/item/electronic_assembly
	name = "electronic assembly"
	/// The export window's view (made on first export).
	var/datum/ic_export_view/export_view
	desc = "It's a case, for building small electronics with."
	w_class = ITEMSIZE_SMALL
	icon = 'icons/obj/integrated_electronics/electronic_setups.dmi'
	icon_state = "setup_small"
	show_messages = TRUE
	var/max_components = IC_COMPONENTS_BASE
	var/max_complexity = IC_COMPLEXITY_BASE
	var/opened = FALSE
	var/can_anchor = FALSE // If true, wrenching it will anchor it.
	var/obj/item/cell/device/battery = null // Internal cell which most circuits need to work.
	var/net_power = 0 // Set every tick, to display how much power is being drawn in total.
	var/detail_color = COLOR_ASSEMBLY_BLACK
	var/locked = FALSE // If true, the assembly cannot be opened with a crowbar
	var/tmp/obj/item/card/id/locked_by	// The ID that locked this assembly
	var/tmp/obj/item/card/id/access_card	// ID card for door access
	var/list/component_positions // Stores circuit positions as list of lists: list("ref" = ref, "x" = x, "y" = y)

CAPABILITIES(/obj/item/electronic_assembly)
	owns_one(nameof(export_view), /datum/ic_export_view)
	every(2 SECONDS, then(PROC_REF(assembly_power_step)), when = nameof(power_relevant))
	op("assembly_self", in_hand(), label("Use"),
		asks(/datum/prompt/choice, fields = list("question" = "What do you want to interact with?", "title" = "Interaction", "choices" = computed(PROC_REF(input_choices)), "timeout" = 0), step = "k_input"),
		then(PROC_REF(interaction_self)))
	op("assembly_item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))
	op("assembly_robot_use", remote(), when(req_actor_kind(/mob/living/silicon/robot)), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(assembly_robot_use)))
	op("assembly_rename", menu(), label("Rename Circuit"), needs(carried()), then(PROC_REF(assembly_rename_op)))
	interface("ICAssembly", state = nameof(GLOB.tgui_physical_state))
	without("ui_open")
	op("export_circuit", ui_act("export_circuit"), then(PROC_REF(ui_act_export_circuit)))
	op("rename", ui_act("rename"), then(PROC_REF(ui_act_rename)))
	op("remove_cell", ui_act("remove_cell"), then(PROC_REF(ui_act_remove_cell)))
	op("wire_internal", ui_act("wire_internal", arg("pin1", schema_ref(/datum/integrated_io)), arg("pin2", schema_ref(/datum/integrated_io))), then(PROC_REF(ui_act_wire_internal)))
	op("remove_all_wires", ui_act("remove_all_wires", arg("pin", schema_ref(/datum/integrated_io))), then(PROC_REF(ui_act_remove_all_wires)))
	op("open_circuit", ui_act("open_circuit", arg("ref", schema_ref(/obj/item/integrated_circuit))), then(PROC_REF(ui_act_open_circuit)))
	op("remove_circuit", ui_act("remove_circuit", arg("ref", schema_ref(/obj/item/integrated_circuit))), then(PROC_REF(ui_act_remove_circuit)))
	op("update_component_position", ui_act("update_component_position", arg("ref", schema_ref(/obj/item/integrated_circuit)), arg("x", num()), arg("y", num())), then(PROC_REF(ui_act_update_component_position)))

/// Cached flag: TRUE when this assembly has at least one circuit that draws or makes power (so
/// handle_idle_power() actually has work to do). Recomputed on circuit/cell add/remove via
/// Entered()/Exited(); null until first computed.
/obj/item/electronic_assembly/var/tmp/power_relevant = null
TRACKED(/obj/item/electronic_assembly, power_relevant)
TRACKED(/obj/item/electronic_assembly, opened)
TRACKED(/obj/item/electronic_assembly, detail_color)

/// Idle power every 2 s while there is power-relevant work (a battery plus a circuit that makes or draws idle power).
/obj/item/electronic_assembly/proc/assembly_power_step(datum/act/timer/A)
	var/seconds_per_tick = 20 // the interval, in deciseconds, as the old sweep passed it
	handle_idle_power(seconds_per_tick)

// Any circuit or cell entering/leaving contents can change whether there's power-relevant work to
// do: recompute now, so set_power_relevant() raises only on a real change.
/obj/item/electronic_assembly/Entered(atom/movable/AM, atom/old_loc)
	. = ..()
	if(istype(AM, /obj/item/integrated_circuit) || istype(AM, /obj/item/cell))
		recompute_power_relevant()

/obj/item/electronic_assembly/Exited(atom/movable/AM, atom/new_loc)
	. = ..()
	if(istype(AM, /obj/item/integrated_circuit) || istype(AM, /obj/item/cell))
		recompute_power_relevant()

// (Re)computes whether handle_idle_power() has anything to do: a battery to draw
// from plus at least one circuit that makes or draws idle power.
/obj/item/electronic_assembly/proc/recompute_power_relevant()
	var/relevant = FALSE
	if(battery && battery.loc == src)
		for(var/obj/item/integrated_circuit/IC in contents)
			if(IC.power_draw_idle || istype(IC, /obj/item/integrated_circuit/passive/power))
				relevant = TRUE
				break
	set_power_relevant(relevant)

/obj/item/electronic_assembly/proc/handle_idle_power(seconds_per_tick)
	net_power = 0 // Reset this. This gets increased/decreased with [give/draw]_power() outside of this loop.

	// Early-out: no battery / nothing power-relevant means double-iterating
	// contents every SSobj tick is pure waste. Cache the verdict, recompute only
	// when a circuit/battery is added or removed (Entered/Exited null the flag).
	if(isnull(power_relevant))
		recompute_power_relevant()
	if(!power_relevant)
		return

	// Normalize the per-tick draw to the current SSobj wait so the power economy
	// is unchanged while the rate decouples from the scheduler. seconds_per_tick
	// arrives in deciseconds from the processing subsystem; convert to seconds.
	var/draw_scale = (seconds_per_tick / 10) / IC_IDLE_POWER_BASELINE_SPT
	if(draw_scale <= 0)
		draw_scale = 1

	// First we handle passive sources. Most of these make power so they go first.
	for(var/obj/item/integrated_circuit/passive/power/P in contents)
		P.handle_passive_energy()

	// Now we handle idle power draw.
	for(var/obj/item/integrated_circuit/IC in contents)
		if(IC.power_draw_idle)
			if(!draw_power(IC.power_draw_idle * draw_scale))
				IC.power_fail()

/obj/item/electronic_assembly/proc/check_interactivity(mob/user)
	return tgui_status(user, GLOB.tgui_physical_state) == STATUS_INTERACTIVE

/obj/item/electronic_assembly/get_cell()
	return battery

// TGUI

/obj/item/electronic_assembly/ui_assets(mob/user)
	return list(
		get_asset_datum(/datum/asset/simple/circuit_assets)
	)

/obj/item/electronic_assembly/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["max_components"] = max_components
	data["max_complexity"] = max_complexity
	data["assembly_name"] = name
	var/list/merged_1 = ui_data_obj_item_electronic_assembly(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/item/electronic_assembly's window data.
/obj/item/electronic_assembly/proc/ui_data_obj_item_electronic_assembly(mob/user, datum/tgui/_ui, datum/tgui_state/_state)
	var/list/data = list()

	var/total_parts = 0
	var/total_complexity = 0
	FOR_REAL_CONTENTS(var/obj/item/integrated_circuit/part, src)
		total_parts += part.size
		total_complexity = total_complexity + part.complexity

	data["total_parts"] = total_parts
	data["total_complexity"] = total_complexity

	data["battery_charge"] = round(battery?.charge, 0.1)
	data["battery_max"] = round(battery?.maxcharge, 0.1)
	data["net_power"] = net_power / CELLRATE

	// Include export data - the UI component will handle displaying it if needed
	data["export_data"] = serialize_electronic_assembly()

	var/list/circuits = list()
	FOR_REAL_CONTENTS(var/obj/item/integrated_circuit/circuit, src)
		UNTYPED_LIST_ADD(circuits, circuit.tgui_data(user))
	data["circuits"] = circuits

	// Include component positions for UI restoration
	data["component_positions"] = (component_positions || list())

	return data

/obj/item/electronic_assembly/proc/ui_act_export_circuit(datum/act/op/A)
	var/mob/user = A.actor
	if(!LAZYLEN(contents))
		to_chat(user, span_warning("There's nothing in the [src] to export!"))
		return TRUE
	if(!export_view)
		rel_set(src, nameof(/obj/item/electronic_assembly::export_view), new /datum/ic_export_view(src))
	export_view.tgui_interact(user)
	return TRUE

/// The assembly's export window, a second window next to its editor. Owned by the assembly
/// (implicit OWN through rel_set), so it goes with it.
/datum/ic_export_view
	/// Relation view: the assembly this window exports.
	var/tmp/obj/item/electronic_assembly/host_assembly

/datum/ic_export_view/New(obj/item/electronic_assembly/assembly)
	rel_set(src, nameof(host_assembly), assembly)

/datum/ic_export_view/proc/assembly() as /obj/item/electronic_assembly
	return host_assembly

CAPABILITIES(/datum/ic_export_view)
	interface("ICExport", title = "Circuit Export")
	ui_shape(export_data = schema_text(), assembly_name = schema_text())

/datum/ic_export_view/tgui_host(mob/user)
	return assembly() || src

/datum/ic_export_view/tgui_state(mob/user)
	return assembly()?.tgui_state(user) || ..()

/// /datum/ic_export_view's window data.
/datum/ic_export_view/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	return assembly()?.tgui_data(user) || list()

/datum/ic_export_view/tgui_static_data(mob/user)
	return assembly()?.tgui_static_data(user) || list()

// Actual assembly actions

/obj/item/electronic_assembly/proc/ui_act_rename(datum/act/op/A)
	var/mob/user = A.actor
	electronic_assembly_verb_rename(user)
	return TRUE

/obj/item/electronic_assembly/proc/ui_act_remove_cell(datum/act/op/A)
	var/mob/user = A.actor
	if(!battery)
		to_chat(user, span_warning("There's no power cell to remove from \the [src]."))
		return FALSE
	var/turf/T = get_turf(src)
	var/obj/item/cell/device/removed = rel_take(src, nameof(/obj/item/electronic_assembly::battery))
	removed.forceMove(T)
	play_sfx(T, SFX_ITEMS_CROWBAR)
	to_chat(user, span_notice("You pull 	he [removed] out of 	he [src]'s power supplier."))
	return TRUE

	// Circuit actions

/obj/item/electronic_assembly/proc/ui_act_wire_internal(datum/act/op/A, pin1_arg, pin2_arg)
	var/datum/integrated_io/pin1 = pin1_arg
	if(!istype(pin1))
		return
	var/datum/integrated_io/pin2 = pin2_arg
	if(!istype(pin2))
		return

	var/obj/item/integrated_circuit/holder1 = pin1.holder()
	if(!istype(holder1) || holder1.loc != src || holder1.assembly() != src)
		return

	var/obj/item/integrated_circuit/holder2 = pin2.holder()
	if(!istype(holder2) || holder2.loc != src || holder2.assembly() != src)
		return

	// Wiring the same pin will unwire it
	if(pin2 in pin1.linked)
		rel_remove(pin1, nameof(/datum/integrated_io::linked), pin2)
		rel_remove(pin2, nameof(/datum/integrated_io::linked), pin1)
	else
		rel_add(pin1, nameof(/datum/integrated_io::linked), pin2)
		rel_add(pin2, nameof(/datum/integrated_io::linked), pin1)

	return TRUE

/obj/item/electronic_assembly/proc/ui_act_remove_all_wires(datum/act/op/A, pin)
	var/datum/integrated_io/pin1 = pin
	if(!istype(pin1))
		return

	var/obj/item/integrated_circuit/holder1 = pin1.holder()
	if(!istype(holder1) || holder1.loc != src || holder1.assembly() != src)
		return

	for(var/datum/integrated_io/other as anything in pin1.linked)
		rel_remove(other, nameof(/datum/integrated_io::linked), pin1)

	rel_clear(pin1, nameof(/datum/integrated_io::linked))

	return TRUE

/obj/item/electronic_assembly/proc/ui_act_open_circuit(datum/act/op/A, ref)
	var/mob/user = A.actor
	var/datum/tgui/ui = A.window_ui() || SStgui.get_open_ui(user, src) // the window the button was pressed in
	if(!isnull(ref) && !(ref in contents_of(src)))
		return FALSE
	var/obj/item/integrated_circuit/C = ref
	if(!istype(C))
		return
	C.tgui_interact(user, null, ui)
	return TRUE

/obj/item/electronic_assembly/proc/ui_act_remove_circuit(datum/act/op/A, ref)
	var/mob/user = A.actor
	if(!isnull(ref) && !(ref in contents_of(src)))
		return FALSE
	var/obj/item/integrated_circuit/C = ref
	if(!istype(C))
		return
	C.remove(user)
	return TRUE

/obj/item/electronic_assembly/proc/ui_act_update_component_position(datum/act/op/A, ref, x, y)
	if(!isnull(ref) && !(ref in contents_of(src)))
		return FALSE
	var/obj/item/integrated_circuit/C = ref
	if(!istype(C))
		return FALSE

	var/new_x = x
	var/new_y = y
	if(!isnum(new_x) || !isnum(new_y))
		return FALSE

	// Find existing position entry or create new one
	var/found = FALSE
	for(var/list/pos_data in component_positions)
		if(pos_data["ref"] == REF(C))
			pos_data["x"] = new_x
			pos_data["y"] = new_y
			found = TRUE
			break

	if(!found)
		UNTYPED_LIST_ADD(component_positions, list("ref" = REF(C), "x" = new_x, "y" = new_y))

	return TRUE
// End TGUI

/// Old Rename Circuit verb: Rename your circuit, useful to stay organized.
/obj/item/electronic_assembly/proc/electronic_assembly_verb_rename(mob/user)
	var/mob/M = user
	if(!check_interactivity(M))
		return

	if(!ismob(M) || QDELETED(M))
		return
	open_request(src, /datum/prompt/text/electronics_rename, PROC_REF(rename_entered), answerer = M, question = "What do you want to name this?", default = name)

/obj/item/electronic_assembly/proc/rename_entered(datum/act/request/A)
	var/datum/prompt/text/electronics_rename/request = A.request
	if(request.captures_gone())
		return
	if(!A.answer)
		if(request.outcome == REQ_CANCELLED && !isnull(request.value))
			SStgui.update_uis(src)
		return
	apply_rename(A)
	SStgui.update_uis(src)

/obj/item/electronic_assembly/proc/apply_rename(datum/act/request/A)
	var/mob/M = A.request.answerer
	if(!check_interactivity(M))
		return
	var/_answer_k272 = A.answer.value
	var/input = sanitizeSafe(_answer_k272, MAX_NAME_LEN)
	if(src && input)
		to_chat(M, span_notice("The machine now has a label reading '[input]'."))
		name = input

/obj/item/electronic_assembly/proc/can_move()
	return FALSE

/obj/item/electronic_assembly/draw(datum/look/look)
	..()
	// Locked-assembly sprites are not made yet; only the open state changes the base sprite.
	var/shown = look.state("[initial(icon_state)][opened ? "-open" : ""]")
	if(detail_color == COLOR_ASSEMBLY_BLACK) // Black looks almost but not exactly like the base sprite, so draw no detail overlay.
		return
	look.overlay(look_appearance('icons/obj/integrated_electronics/electronic_setups.dmi', "[shown]-color", color = detail_color))

/obj/item/electronic_assembly/examine(mob/user)
	. = ..()
	if(Adjacent(user))
		FOR_REAL_CONTENTS(var/obj/item/integrated_circuit/IC, src)
			// Make sure there's actually examine text to prevent empty lines being printed for EVERY component!
			var/examine_text = IC.external_examine(user)
			if (length(examine_text))
				. += examine_text
		if(opened)
			tgui_interact(user)

/obj/item/electronic_assembly/proc/get_part_complexity()
	. = 0
	for(var/obj/item/integrated_circuit/part in contents)
		. += part.complexity

/obj/item/electronic_assembly/proc/get_part_size()
	. = 0
	for(var/obj/item/integrated_circuit/part in contents)
		. += part.size

// Returns true if the circuit made it inside.
/obj/item/electronic_assembly/proc/add_circuit(obj/item/integrated_circuit/IC, mob/user)
	if(!opened)
		to_chat(user, span_warning("\The [src] isn't opened, so you can't put anything inside.  Try using a crowbar."))
		return FALSE

	if(IC.w_class > src.w_class)
		to_chat(user, span_warning("\The [IC] is way too big to fit into \the [src]."))
		return FALSE

	var/total_part_size = get_part_size()
	var/total_complexity = get_part_complexity()

	if((total_part_size + IC.size) > max_components)
		to_chat(user, span_warning("You can't seem to add the '[IC.name]', as there's insufficient space."))
		return FALSE
	if((total_complexity + IC.complexity) > max_complexity)
		to_chat(user, span_warning("You can't seem to add the '[IC.name]', since this setup's too complicated for the case."))
		return FALSE

	if(!IC.forceMove(src))
		return FALSE

	rel_set(IC, nameof(IC.assembly), src)

	return TRUE

// Non-interactive version of above that always succeeds, intended for build-in circuits that get added on assembly initialization.
/obj/item/electronic_assembly/proc/force_add_circuit(obj/item/integrated_circuit/IC)
	IC.forceMove(src)
	rel_set(IC, nameof(IC.assembly), src)

/obj/item/electronic_assembly/afterattack(atom/target, mob/user, proximity)
	var/scanned = FALSE
	if(proximity)
		// Existing sensor support
		for(var/obj/item/integrated_circuit/input/sensor/S in contents)
			if(S.scan(target))
				scanned = TRUE
		if(scanned)
			act_message(user, src, others = span_infoplain(span_bold("%U%") + " waves %T% around [target]."))

	// Support for reference grabber + future ranged circuitry.
	for(var/obj/item/integrated_circuit/input/reference_grabber/G in contents)
		G.afterattack(target, user, proximity, null)

/// Old attackby.
/obj/item/electronic_assembly/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(istype(I, /obj/item/integrated_circuit))
		if(!user.unEquip(I) && I.loc == user) //an item a gripper holds is not in the actor's own inventory, so it is no refusal
			return OP_PASS
		if(add_circuit(I, user))
			to_chat(user, span_notice("You slide \the [I] inside \the [src]."))
			play_sfx(src, SFX_ITEMS_DECONSTRUCT)
			tgui_interact(user)
			return OP_OK

	else if((istype(I, /obj/item/card/id) || istype(I, /obj/item/pda)) && !opened)
		var/obj/item/card/id/id_card = null

		if(istype(I, /obj/item/card/id))
			id_card = I
		else
			var/obj/item/pda/pda = I
			id_card = pda.id

		if(!id_card)
			to_chat(user, span_warning("You need an ID card to lock this assembly!"))
			return OP_PASS

		if(locked)
			// Trying to unlock
			if(locked_by() && id_card.registered_name == locked_by().registered_name)
				locked = FALSE
				rel_clear(src, nameof(locked_by))
				to_chat(user, span_notice("You unlock \the [src]."))
			else
				to_chat(user, span_warning("Access denied. This assembly was locked by [locked_by() ? locked_by().registered_name : "someone else"]."))
			return OP_OK
		else
			// Trying to lock
			locked = TRUE
			rel_set(src, nameof(locked_by), id_card)
			to_chat(user, span_notice("You lock \the [src]. Now only your ID card can unlock it."))
			return OP_OK

	else if(istype(I, /obj/item/integrated_electronics/wirer) || istype(I, /obj/item/integrated_electronics/debugger))
		if(opened)
			tgui_interact(user)
			return OP_OK
		else
			to_chat(user, span_warning("\The [src] isn't opened, so you can't fiddle with the internal components.  \
			Try using a crowbar."))
			return OP_PASS

	else if(istype(I, /obj/item/integrated_electronics/detailer))
		var/obj/item/integrated_electronics/detailer/D = I
		set_detail_color(D.detail_color)

	else if(istype(I, /obj/item/cell/device))
		if(!opened)
			to_chat(user, span_warning("\The [src] isn't opened, so you can't put anything inside.  Try using a crowbar."))
			return OP_PASS
		if(battery)
			to_chat(user, span_warning("\The [src] already has \a [battery] inside.  Remove it first if you want to replace it."))
			return OP_PASS
		var/obj/item/cell/device/cell = I
		if(!move_into(src, nameof(src.battery), cell, user))
			return OP_PASS
		play_sfx(src, SFX_ITEMS_DECONSTRUCT)
		to_chat(user, span_notice("You slot \the [cell] inside \the [src]'s power supplier."))
		tgui_interact(user)
		return OP_OK

	else
		return OP_DECLINE
	return OP_PASS

/obj/item/electronic_assembly/wrench_act(mob/user, obj/item/tool)
	if(!can_anchor)
		return FALSE
	set_anchored(!anchored)
	to_chat(user, span_notice("You've [anchored ? "" : "un"]secured \the [src] to \the [get_turf(src)]."))
	if(anchored)
		on_anchored()
	else
		on_unanchored()
	playsound(src, tool.usesound, 50, TRUE)
	return TRUE

/obj/item/electronic_assembly/crowbar_act(mob/user, obj/item/tool)
	if(locked)
		to_chat(user, span_warning("\The [src] is locked! You cannot open it with a crowbar."))
		return ITEM_INTERACT_BLOCKING
	playsound(src, tool.usesound, 50, TRUE)
	set_opened(!opened)
	to_chat(user, span_notice("You [opened ? "opened" : "closed"] \the [src]."))
	return ITEM_INTERACT_SUCCESS

/obj/item/electronic_assembly/screwdriver_act(mob/user, obj/item/tool)
	if(opened)
		tgui_interact(user)
		return ITEM_INTERACT_SUCCESS
	to_chat(user, span_warning("\The [src] isn't opened, so you can't fiddle with the internal components. Try using a crowbar."))
	return ITEM_INTERACT_BLOCKING

/// The Rename Circuit menu entry.
/obj/item/electronic_assembly/proc/assembly_rename_op(datum/act/op/A)
	electronic_assembly_verb_rename(A.actor)
	return OP_OK

/// The names the self-use question offers.
/obj/item/electronic_assembly/proc/input_choices(datum/act/op/A)
	var/list/options = input_prompt_options()
	return options[1]

/// Old attack_self: ask which input circuit to use, then ask that circuit for its input.
/obj/item/electronic_assembly/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(!check_interactivity(user))
		return OP_OK
	if(opened)
		tgui_interact(user)
	var/list/options = input_prompt_options()
	var/list/input_selection = options[1]
	var/list/available_inputs = options[2]
	var/selection = A.step_value("k_input")
	var/obj/item/integrated_circuit/input/choice
	if(selection)
		var/index = input_selection.Find(selection)
		choice = available_inputs[index]
	if(choice)
		choice.ask_for_input(user)
	SStgui.update_uis(src)
	return OP_OK

/obj/item/electronic_assembly/proc/input_prompt_options()
	var/list/input_selection = list()
	var/list/available_inputs = list()
	for(var/obj/item/integrated_circuit/input/input in contents)
		if(input.can_be_asked_input)
			available_inputs.Add(input)
			var/i = 0
			for(var/obj/item/integrated_circuit/s in available_inputs)
				if(s.name == input.name && s.displayed_name == input.displayed_name && s != input)
					i++
			var/disp_name= "[input.displayed_name] \[[input.name]\]"
			if(i)
				disp_name += " ([i+1])"
			input_selection.Add(disp_name)

	return list(input_selection, available_inputs)

/// Old attack_robot: an adjacent cyborg uses it in hand; otherwise the default.
/obj/item/electronic_assembly/proc/assembly_robot_use(datum/act/op/A)
	var/mob/user = A.actor
	if(!Adjacent(user))
		return OP_DECLINE
	attack_self(user)
	return OP_OK

// Returns true if power was successfully drawn.
/obj/item/electronic_assembly/proc/draw_power(amount)
	if(battery)
		var/lost = battery.use(amount * CELLRATE)
		net_power -= lost
		return lost
	return FALSE

// Ditto for giving.
/obj/item/electronic_assembly/proc/give_power(amount)
	if(battery)
		var/gained = battery.give(amount * CELLRATE)
		net_power += gained
		return TRUE
	return FALSE

/obj/item/electronic_assembly/proc/on_anchored()
	for(var/obj/item/integrated_circuit/IC in contents)
		IC.on_anchored()

/obj/item/electronic_assembly/proc/on_unanchored()
	for(var/obj/item/integrated_circuit/IC in contents)
		IC.on_unanchored()

// Bump functionality, for pathfinding circuits. (Droid circuit assembly types)
/obj/item/electronic_assembly/Bump(atom/AM)
	..()
	if(can_move())
		// Check if it's an airlock or windoor. (Prevents opening blast doors and shutters)
		if(istype(AM, /obj/machinery/door/airlock) || istype(AM, /obj/machinery/door/window))
			var/obj/machinery/door/D = AM
			// Only open doors that we have access to
			if(D.check_access(src))
				D.open()

/obj/item/electronic_assembly/check_access(obj/item/I)
	if(access_card())
		return access_card().check_access(I)
	return ..()  // Fall back to default behavior if no access_card

// Returns TRUE if I is something that could/should have a valid interaction. Used to tell circuitclothes to hit the circuit with something instead of the clothes
/obj/item/electronic_assembly/proc/is_valid_tool(obj/item/I)
	return I.has_tool_quality(TOOL_CROWBAR) || I.has_tool_quality(TOOL_SCREWDRIVER) || istype(I, /obj/item/integrated_circuit) || istype(I, /obj/item/cell/device) || istype(I, /obj/item/integrated_electronics)

/obj/item/electronic_assembly/ownership()
	. = ..()
	. += owns(nameof(battery), policy = OWN_CONTAINED, starts = /obj/item/cell/device)

/// ID card for door access (a relation view: null once that is deleted).
/obj/item/electronic_assembly/proc/access_card() as /obj/item/card/id
	return access_card

/// The ID that locked this assembly (a relation view: null once that is deleted).
/obj/item/electronic_assembly/proc/locked_by() as /obj/item/card/id
	return locked_by
