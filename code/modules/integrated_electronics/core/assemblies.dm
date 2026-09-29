// Here is where the base definition lives.
// Specific subtypes are in their own folder.

/obj/item/electronic_assembly
	name = "electronic assembly"
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
	/// Cached flag: TRUE when this assembly has at least one circuit that draws or
	/// makes power (so handle_idle_power() actually has work to do). Invalidated to
	/// null on circuit add/remove via Entered()/Exited() and recomputed lazily.
	var/tmp/power_relevant = null

DECLARE_DEFAULT_CHILD(/obj/item/electronic_assembly, "battery", /obj/item/cell/device)

/// Has power-relevant work (a battery plus a circuit that makes or draws idle power). Entered()/
/// Exited() drop the cache and raise CHANGE_EXPLICIT; the value is recomputed when next read.
OM_DERIVE_FIELD(/obj/item/electronic_assembly, has_power_work, CHANGE_EXPLICIT)
DECLARE_PERIODIC_WHILE(/obj/item/electronic_assembly, PERIODIC_SLOW, "has_power_work")

/obj/item/electronic_assembly/proc/has_power_work()
	if(isnull(power_relevant))
		recompute_power_relevant()
	return power_relevant

/obj/item/electronic_assembly/periodic_step(seconds_per_tick)
	handle_idle_power(seconds_per_tick)

// Cache invalidation: any circuit entering/leaving contents can change whether
// there's power-relevant work to do. Recomputed lazily when has_power_work() is next read.
/obj/item/electronic_assembly/Entered(atom/movable/AM, atom/old_loc)
	. = ..()
	if(istype(AM, /obj/item/integrated_circuit) || istype(AM, /obj/item/cell))
		power_relevant = null
		om_changed(src, CHANGE_EXPLICIT)

/obj/item/electronic_assembly/Exited(atom/movable/AM, atom/new_loc)
	. = ..()
	if(istype(AM, /obj/item/integrated_circuit) || istype(AM, /obj/item/cell))
		power_relevant = null
		om_changed(src, CHANGE_EXPLICIT)

// (Re)computes whether handle_idle_power() has anything to do: a battery to draw
// from plus at least one circuit that makes or draws idle power.
/obj/item/electronic_assembly/proc/recompute_power_relevant()
	power_relevant = FALSE
	if(!battery || battery.loc != src)
		return
	for(var/obj/item/integrated_circuit/IC in contents)
		if(IC.power_draw_idle || istype(IC, /obj/item/integrated_circuit/passive/power))
			power_relevant = TRUE
			return

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
/obj/item/electronic_assembly/tgui_state(mob/user)
	return GLOB.tgui_physical_state

/obj/item/electronic_assembly/tgui_interact(mob/user, datum/tgui/ui, datum/tgui/parent_ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "ICAssembly", name, parent_ui)
		ui.open()

/obj/item/electronic_assembly/ui_assets(mob/user)
	return list(
		get_asset_datum(/datum/asset/simple/circuit_assets)
	)

/obj/item/electronic_assembly/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = ..()

	var/total_parts = 0
	var/total_complexity = 0
	FOR_REAL_CONTENTS(var/obj/item/integrated_circuit/part, src)
		total_parts += part.size
		total_complexity = total_complexity + part.complexity

	data["total_parts"] = total_parts
	data["max_components"] = max_components
	data["total_complexity"] = total_complexity
	data["max_complexity"] = max_complexity

	data["battery_charge"] = round(battery?.charge, 0.1)
	data["battery_max"] = round(battery?.maxcharge, 0.1)
	data["net_power"] = net_power / CELLRATE

	// Include export data - the UI component will handle displaying it if needed
	data["export_data"] = serialize_electronic_assembly()
	data["assembly_name"] = name

	var/list/circuits = list()
	FOR_REAL_CONTENTS(var/obj/item/integrated_circuit/circuit, src)
		UNTYPED_LIST_ADD(circuits, circuit.tgui_data(user, ui, state))
	data["circuits"] = circuits

	// Include component positions for UI restoration
	data["component_positions"] = (component_positions || list())

	return data

/obj/item/electronic_assembly/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	if(..())
		return TRUE

	switch(action)
		if("export_circuit")
			if(!LAZYLEN(contents))
				to_chat(ui.user, span_warning("There's nothing in the [src] to export!"))
				return TRUE
			var/datum/tgui/window = new(ui.user, src, "ICExport", "Circuit Export")
			window.open()
			return TRUE

		// Actual assembly actions
		if("rename")
			electronic_assembly_verb_rename(ui.user)
			return TRUE

		if("remove_cell")
			if(!battery)
				to_chat(ui.user, span_warning("There's no power cell to remove from \the [src]."))
				return FALSE
			var/turf/T = get_turf(src)
			var/obj/item/cell/device/removed = own_take(src, "battery")
			removed.forceMove(T)
			play_sfx(T, SFX_ITEMS_CROWBAR)
			to_chat(ui.user, span_notice("You pull 	he [removed] out of 	he [src]'s power supplier."))
			return TRUE

		// Circuit actions
		if("wire_internal")
			var/datum/integrated_io/pin1 = locate(params["pin1"])
			if(!istype(pin1))
				return
			var/datum/integrated_io/pin2 = locate(params["pin2"])
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
				rel_remove(pin1, "linked", pin2)
				rel_remove(pin2, "linked", pin1)
			else
				rel_add(pin1, "linked", pin2)
				rel_add(pin2, "linked", pin1)

			return TRUE

		if("remove_all_wires")
			var/datum/integrated_io/pin1 = locate(params["pin"])
			if(!istype(pin1))
				return

			var/obj/item/integrated_circuit/holder1 = pin1.holder()
			if(!istype(holder1) || holder1.loc != src || holder1.assembly() != src)
				return

			for(var/datum/integrated_io/other as anything in pin1.linked)
				rel_remove(other, "linked", pin1)

			rel_clear(pin1, "linked")

			return TRUE

		if("open_circuit")
			var/obj/item/integrated_circuit/C = locate_within(src, params["ref"])
			if(!istype(C))
				return
			C.tgui_interact(ui.user, null, ui)
			return TRUE

		if("remove_circuit")
			var/obj/item/integrated_circuit/C = locate_within(src, params["ref"])
			if(!istype(C))
				return
			C.remove(ui.user)
			return TRUE

		if("update_component_position")
			var/obj/item/integrated_circuit/C = locate_within(src, params["ref"])
			if(!istype(C))
				return FALSE

			var/new_x = params["x"]
			var/new_y = params["y"]
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

	return FALSE
// End TGUI

/// Old Rename Circuit verb: Rename your circuit, useful to stay organized.
/obj/item/electronic_assembly/proc/electronic_assembly_verb_rename(mob/user, obj/item/held, datum/interaction/interaction)
	var/mob/M = user
	if(!check_interactivity(M))
		return

	var/_answer_k272 = rerun_ask(user, "k272", PROC_REF(electronic_assembly_verb_rename), args, /datum/om/prompt/text, message = "What do you want to name this?", title = "Rename", default = src.name, max_length = MAX_NAME_LEN, encode = FALSE)
	if(isnull(_answer_k272))
		return
	var/input = sanitizeSafe(_answer_k272, MAX_NAME_LEN)
	if(src && input)
		to_chat(M, span_notice("The machine now has a label reading '[input]'."))
		name = input

/obj/item/electronic_assembly/proc/can_move()
	return FALSE

/obj/item/electronic_assembly/update_icon()
	if(opened)
		icon_state = initial(icon_state) + "-open"
	// else if(locked)
		// For when I finish the locked assembly sprites.
		// icon_state = initial(icon_state) // + "-locked" would be added once sprites are made
	else
		icon_state = initial(icon_state)
	cut_overlays()
	if(detail_color == COLOR_ASSEMBLY_BLACK) //Black colored overlay looks almost but not exactly like the base sprite, so just cut the overlay and avoid it looking kinda off.
		return
	var/mutable_appearance/detail_overlay = mutable_appearance('icons/obj/integrated_electronics/electronic_setups.dmi', "[icon_state]-color")
	detail_overlay.color = detail_color
	add_overlay(detail_overlay)

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

	rel_set(IC, "assembly", src)

	return TRUE

// Non-interactive version of above that always succeeds, intended for build-in circuits that get added on assembly initialization.
/obj/item/electronic_assembly/proc/force_add_circuit(obj/item/integrated_circuit/IC)
	IC.forceMove(src)
	rel_set(IC, "assembly", src)

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
/obj/item/electronic_assembly/proc/interaction_item(mob/user, obj/item/I, datum/interaction/interaction)
	if(istype(I, /obj/item/integrated_circuit))
		if(!user.unEquip(I) && !isrobot(user)) //Robots cannot de-equip items in grippers.
			return INTERACTION_HANDLED_PASS
		if(add_circuit(I, user))
			to_chat(user, span_notice("You slide \the [I] inside \the [src]."))
			play_sfx(src, SFX_ITEMS_DECONSTRUCT)
			tgui_interact(user)
			return TRUE

	else if((istype(I, /obj/item/card/id) || istype(I, /obj/item/pda)) && !opened)
		var/obj/item/card/id/id_card = null

		if(istype(I, /obj/item/card/id))
			id_card = I
		else
			var/obj/item/pda/pda = I
			id_card = pda.id

		if(!id_card)
			to_chat(user, span_warning("You need an ID card to lock this assembly!"))
			return INTERACTION_HANDLED_PASS

		if(locked)
			// Trying to unlock
			if(locked_by() && id_card.registered_name == locked_by().registered_name)
				locked = FALSE
				rel_clear(src, "locked_by")
				to_chat(user, span_notice("You unlock \the [src]."))
				update_icon()
			else
				to_chat(user, span_warning("Access denied. This assembly was locked by [locked_by() ? locked_by().registered_name : "someone else"]."))
			return TRUE
		else
			// Trying to lock
			locked = TRUE
			rel_set(src, "locked_by", id_card)
			to_chat(user, span_notice("You lock \the [src]. Now only your ID card can unlock it."))
			update_icon()
			return TRUE

	else if(istype(I, /obj/item/integrated_electronics/wirer) || istype(I, /obj/item/integrated_electronics/debugger))
		if(opened)
			tgui_interact(user)
			return TRUE
		else
			to_chat(user, span_warning("\The [src] isn't opened, so you can't fiddle with the internal components.  \
			Try using a crowbar."))
			return INTERACTION_HANDLED_PASS

	else if(istype(I, /obj/item/integrated_electronics/detailer))
		var/obj/item/integrated_electronics/detailer/D = I
		detail_color = D.detail_color
		update_icon()

	else if(istype(I, /obj/item/cell/device))
		if(!opened)
			to_chat(user, span_warning("\The [src] isn't opened, so you can't put anything inside.  Try using a crowbar."))
			return INTERACTION_HANDLED_PASS
		if(battery)
			to_chat(user, span_warning("\The [src] already has \a [battery] inside.  Remove it first if you want to replace it."))
			return INTERACTION_HANDLED_PASS
		var/obj/item/cell/device/cell = I
		user.drop_item(cell)
		cell.forceMove(src)
		own_set(src, "battery", cell)
		play_sfx(src, SFX_ITEMS_DECONSTRUCT)
		to_chat(user, span_notice("You slot \the [cell] inside \the [src]'s power supplier."))
		tgui_interact(user)
		return TRUE

	else
		return FALSE
	return INTERACTION_HANDLED_PASS

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
	opened = !opened
	to_chat(user, span_notice("You [opened ? "opened" : "closed"] \the [src]."))
	update_icon()
	return ITEM_INTERACT_SUCCESS

/obj/item/electronic_assembly/screwdriver_act(mob/user, obj/item/tool)
	if(opened)
		tgui_interact(user)
		return ITEM_INTERACT_SUCCESS
	to_chat(user, span_warning("\The [src] isn't opened, so you can't fiddle with the internal components. Try using a crowbar."))
	return ITEM_INTERACT_BLOCKING

DECLARE_INTERACTIONS(/obj/item/electronic_assembly, \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
	INTERACT_ROBOT("Use", PROC_REF(assembly_robot_use)), \
	INTERACT_VERB("Rename Circuit", PROC_REF(electronic_assembly_verb_rename), REQ_IN_INVENTORY), \
)

/// Old attack_self.
/obj/item/electronic_assembly/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(!check_interactivity(user))
		return TRUE
	if(opened)
		tgui_interact(user)

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

	var/obj/item/integrated_circuit/input/choice
	if(available_inputs)
		var/selection = rerun_ask(user, "k490", PROC_REF(interaction_self), args, /datum/om/prompt/choice, message = "What do you want to interact with?", title = "Interaction", choices = input_selection)
		if(isnull(selection))
			return TRUE
		if(selection)
			var/index = input_selection.Find(selection)
			choice = available_inputs[index]

	if(choice)
		choice.ask_for_input(user)
	return TRUE

/// Old attack_robot: an adjacent cyborg uses it in hand; otherwise the default.
/obj/item/electronic_assembly/proc/assembly_robot_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(!Adjacent(user))
		return FALSE
	attack_self(user)
	return TRUE

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

OWN(/obj/item/electronic_assembly, battery, OWN_CONTAINED)

/// ID card for door access (a relation view: null once that is deleted).
/obj/item/electronic_assembly/proc/access_card() as /obj/item/card/id
	return access_card

/// The ID that locked this assembly (a relation view: null once that is deleted).
/obj/item/electronic_assembly/proc/locked_by() as /obj/item/card/id
	return locked_by
