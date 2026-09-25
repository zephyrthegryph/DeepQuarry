
// the Area Power Controller (APC), formerly Power Distribution Unit (PDU)
// one per area, needs wire connection to power network through a terminal
//
// All APC #defines live in code/__defines/apc.dm so they are available to the
// icon renderer regardless of include order.
//
// M3: the distributor (channels, cell charging, load shedding) runs in Rust
// (verdigris/domains/power/src/apc.rs) every power step. The APC never polls:
// power_sync() sends its settings, and power_event() applies what Rust
// reports (channels, charging, status, alarm, the cell charge).

/obj/machinery/power/apc/critical
	is_critical = 1

/obj/machinery/power/apc/high
	cell_type = /obj/item/cell/high

/obj/machinery/power/apc/super
	cell_type = /obj/item/cell/super

/obj/machinery/power/apc/super/critical
	is_critical = 1

/obj/machinery/power/apc/hyper
	cell_type = /obj/item/cell/hyper

/obj/machinery/power/apc/alarms_hidden
	alarms_hidden = TRUE

/obj/machinery/power/apc/angled
	icon = 'icons/obj/wall_machines_angled.dmi'

/obj/machinery/power/apc/angled/hidden
	alarms_hidden = TRUE

/obj/machinery/power/apc/angled/offset_apc()
	pixel_x = (dir & 3) ? 0 : (dir == 4 ? 24 : -24)
	pixel_y = (dir & 3) ? (dir == 1 ? 20 : -20) : 0

/obj/machinery/power/apc/hyper/graveyard
	req_access = list(ACCESS_LOST)
	alarms_hidden = TRUE

// ─────────────────────────────────────────────────────────────────────────────
// Main APC type definition
// ─────────────────────────────────────────────────────────────────────────────
/obj/machinery/power/apc

	name = "area power controller"
	desc = "A control terminal for the area electrical systems."
	icon = 'icons/obj/power.dmi'
	icon_state = "apc0"
	layer = ABOVE_WINDOW_LAYER
	anchored = TRUE
	unacidable = TRUE
	use_power = USE_POWER_OFF
	clicksound = "switch"
	req_access = list(ACCESS_ENGINE_EQUIP)
	blocks_emissive = EMISSIVE_BLOCK_NONE
	vis_flags = VIS_HIDE // They have an emissive that looks bad in openspace due to their wall-mounted nature
	flags = WALL_ITEM
	integrity_failure = 0.5

	// ── area/cell wiring ────────────────────────────────────────────────────
	var/area/area
	var/areastring = null
	var/obj/item/cell/cell
	/// Cap for how fast APC cells charge, as a percentage-per-tick.
	/// 0.0005 means cellcharge is capped to ~0.05% per second.
	var/chargelevel = 0.0005
	var/start_charge = 90           // initial cell charge %
	var/cell_type = /obj/item/cell/apc

	// ── physical state ──────────────────────────────────────────────────────
	var/opened = 0                  // 0=closed, 1=opened, 2=cover removed
	var/shorted = 0
	var/grid_check = FALSE
	var/locked = 1
	var/coverlocked = 1
	var/aidisabled = 0
	var/obj/machinery/power/terminal/terminal = null
	var/mob/living/silicon/ai/hacker = null // Malf AI that has full control of this APC.
	var/wiresexposed = FALSE
	powernet = 0                    // set so APCs aren't found as powernet nodes
	var/debug = 0
	var/has_electronics = APC_HAS_ELECTRONICS_NONE
	var/beenhit = 0                 // hit counter, used for Alien claws
	var/emergency_lights = FALSE
	var/is_critical = 0
	var/global/status_overlays = 0
	var/failure_timer = 0
	/// Absolute world.time when an EMP/power failure ends. The legacy counter was
	/// decremented every machinery fire, forcing every disabled APC to poll and
	/// rebuild its icon for minutes after a large explosion.
	var/failure_until = 0
	var/failure_wake_timer
	var/force_update = 0
	var/updating_icon = 0
	var/alarms_hidden = FALSE       // if TRUE, power alarms from this APC are hidden on consoles
	var/nightshift_lights = FALSE
	var/nightshift_setting = NIGHTSHIFT_AUTO
	var/last_nightshift_switch = 0

	// ── delegate datums ──────────────────────────────────────────────────────
	/// The power alarm is raised (as Rust last reported).
	var/power_alarm_raised = FALSE
	/// Power events applied (tests check that a settled APC hears none).
	var/power_event_count = 0
	/// Handles icon_state, overlays, and light.
	var/datum/apc_icon_renderer/icon_renderer = null

	// ── channel state ────────────────────────────────────────────────────────
	// Rust reports these after every power step; power_sync() sends edits.
	var/lighting  = POWERCHAN_ON_AUTO
	var/equipment = POWERCHAN_ON_AUTO
	var/environ   = POWERCHAN_ON_AUTO
	var/operating = 1
	var/charging    = 0
	var/chargemode  = 1
	var/chargecount = 0
	var/autoflag    = 0
	var/longtermpower = 10
	var/lastused_light    = 0
	var/lastused_equip    = 0
	var/lastused_environ  = 0
	var/lastused_charging = 0
	var/lastused_total    = 0
	var/main_status = APC_EXTERNAL_POWER_NOTCONNECTED
	/// Monotonic revision for correction-aware contract power telemetry.
	var/contract_power_revision = 0
	/// Legacy icon-diff state retained for queue_icon_update().
	var/update_state   = -1
	var/update_overlay = -1

// ─────────────────────────────────────────────────────────────────────────────
// Powernet integration
// ─────────────────────────────────────────────────────────────────────────────

/obj/machinery/power/apc/connect_to_network(bind_now = TRUE)
	// Override: APC does not directly connect to the network; it goes through a terminal.
	if(!terminal)
		make_terminal()
	if(terminal)
		terminal.connect_to_network(bind_now)
	power_sync()
	return !!terminal?.powernet

/obj/machinery/power/apc/drain_power(drain_check, surge, amount = 0)
	wake_for_power_dependency()
	if(drain_check)
		return 1

	// Fully draining an APC cell would break charging; reset charging state.
	charging = 0

	var/drained_energy = 0

	// Draw from the grid first (like draining from a cable).
	if(terminal && terminal.powernet)
		terminal.powernet.trigger_warning()
		drained_energy += terminal.powernet.draw_power(amount, terminal)

	// Grid rarely gives the full amount; draw the shortfall from the cell.
	if((drained_energy < amount) && cell)
		drained_energy += cell.drain_power(0, 0, (amount - drained_energy))

	return drained_energy

// ─────────────────────────────────────────────────────────────────────────────
// Lifecycle
// ─────────────────────────────────────────────────────────────────────────────

REGISTRY_MEMBERSHIP(/obj/machinery/power/apc, REGISTRY_APCS)

/obj/machinery/power/apc/Initialize(mapload, ndir, building)
	. = ..()
	set_wires(new /datum/wires/apc(src))

	icon_renderer     = new /datum/apc_icon_renderer()

	// Offset 24 pixels in dir so the APC is embedded in the wall but inside the area.
	if(building)
		set_dir(ndir)

	if(!pixel_x && !pixel_y)
		offset_apc()

	if(building)
		area = get_area(src)
		area.apc = src
		opened    = 1
		operating = 0
		name = "[area.name] APC"
		stat |= MAINT
		update_icon()
		return

	init()
	return INITIALIZE_HINT_LATELOAD

/obj/machinery/power/apc/LateInitialize()
	update()

/obj/machinery/power/apc/Destroy()
	if(failure_wake_timer)
		deltimer(failure_wake_timer)
		failure_wake_timer = null
	if(power_key)
		SSmachines.power_queue(list(POWER_OP_REMOVE_STORAGE, 1, power_key))
	if(power_alarm_raised)
		GLOB.power_alarm.clearAlarm(loc, src)
	REACT_PUBLISH_OWN(src, REACT_KEY_APC, REACT_APC_STATE)
	apply_area_power()

	if(area)
		area.apc = null
		area.power_light  = 0
		area.power_equip  = 0
		area.power_environ = 0
		area.power_change()

	qdel(wires)
	wires = null
	qdel(terminal)
	terminal = null
	if(cell)
		cell.forceMove(loc)
		cell = null

	// Malf AI — remove this APC from AI's hacked list.
	if(hacker && hacker.hacked_apcs && (src in hacker.hacked_apcs))
		hacker.hacked_apcs -= src
	hacker = null

	// Release delegate datums.
	QDEL_NULL(icon_renderer)

	return ..()

/// Something about the APC changed (settings, cell, damage): send it to Rust.
/obj/machinery/power/apc/proc/wake_for_power_dependency()
	REACT_PUBLISH_OWN(src, REACT_KEY_APC, REACT_APC_STATE)
	power_sync()

/// The APC is not a network node: its terminal is.
/obj/machinery/power/apc/disconnect_from_network()
	return FALSE

/obj/machinery/power/apc/power_autoconnect()
	return

/// Sends this APC's settings, cell charge, channel settings and terminal to
/// the Rust power domain. DM's copies are current (every power step writes
/// them back), so sending them is always safe.
/obj/machinery/power/apc/proc/power_sync()
	if(QDELETED(src))
		return
	if(!power_key)
		power_key = power_key_alloc(src)
	var/flags = 0
	if(area?.requires_power && !(stat & (BROKEN | MAINT)) && !failure_timer)
		flags |= POWER_APC_ACTIVE
	if(cell)
		flags |= POWER_APC_HAS_CELL
	if(failure_timer)
		flags |= POWER_APC_FAILED
	if(shorted || grid_check)
		flags |= POWER_APC_SHORTED
	if(operating)
		flags |= POWER_APC_OPERATING
	if(chargemode)
		flags |= POWER_APC_CHARGEMODE
	var/terminal_key = terminal?.power_key || -1
	SSmachines.power_queue(list(POWER_OP_APC, 10, power_key, terminal_key, flags, cell ? cell.maxcharge : 0, chargelevel, cell ? cell.charge : 0, equipment, lighting, environ, autoflag))
	area?.power_loads_changed()

/// A POWER_EV_APC record at `at`: key, charge, eqp, lgt, env, charging,
/// main_status, alarm, autoflag, used eqp/lgt/env/charging/total, area bits.
/obj/machinery/power/apc/proc/power_event(list/events, at)
	power_event_count++
	if(cell)
		cell.charge = events[at + 1]
	var/new_equipment = events[at + 2]
	var/new_lighting = events[at + 3]
	var/new_environ = events[at + 4]
	var/new_charging = events[at + 5]
	var/new_status = events[at + 6]
	var/shown_changed = new_equipment != equipment || new_lighting != lighting || new_environ != environ || new_charging != charging || new_status != main_status
	equipment = new_equipment
	lighting = new_lighting
	environ = new_environ
	charging = new_charging
	main_status = new_status
	autoflag = events[at + 8]
	lastused_equip = events[at + 9]
	lastused_light = events[at + 10]
	lastused_environ = events[at + 11]
	lastused_charging = events[at + 12]
	lastused_total = events[at + 13]
	var/alarm = !!events[at + 7]
	if(alarm != power_alarm_raised)
		power_alarm_raised = alarm
		if(alarm)
			GLOB.power_alarm.triggerAlarm(loc, src, hidden = alarms_hidden)
		else
			GLOB.power_alarm.clearAlarm(loc, src)
	if(shown_changed)
		queue_icon_update()
		apply_area_power()

/obj/machinery/power/apc/proc/offset_apc()
	pixel_x = (dir & 3) ? 0 : (dir == 4 ? 26 : -26)
	pixel_y = (dir & 3) ? (dir == 1 ? 26 : -26) : 0

// APCs are pixel-shifted so they need a full refresh when dir changes.
/obj/machinery/power/apc/set_dir(new_dir)
	..()
	offset_apc()
	if(terminal)
		terminal.disconnect_from_network()
		terminal.set_dir(dir)       // Terminal has same dir as master.
		terminal.connect_to_network()
	return

/obj/machinery/power/apc/proc/energy_fail(duration)
	var/failure_ticks = max(round(duration), 0)
	failure_until = max(failure_until, world.time + failure_ticks * max(SSmachines.wait, 1))
	failure_timer = CEILING(max(failure_until - world.time, 0) / max(SSmachines.wait, 1), 1)
	if(failure_wake_timer)
		deltimer(failure_wake_timer)
	failure_wake_timer = addtimer(CALLBACK(src, PROC_REF(wake_after_failure)), max(failure_until - world.time, 1), TIMER_STOPPABLE)
	queue_icon_update()
	update()

/obj/machinery/power/apc/proc/make_terminal()
	terminal = new /obj/machinery/power/terminal(loc)
	terminal.set_dir(dir)
	terminal.master = src

/obj/machinery/power/apc/proc/init()
	has_electronics = APC_HAS_ELECTRONICS_SECURED // installed and secured
	if(cell_type)
		cell = new cell_type(src)
		cell.charge = start_charge * cell.maxcharge / 100.0

	var/area/A = loc.loc

	if(isarea(A) && !areastring)
		area = A
		name = "\improper [area.name] APC"
	else
		area = get_area_name(areastring)
		name = "\improper [area.name] APC"
	area.apc = src

	if(istype(area, /area/submap))
		alarms_hidden = TRUE

	update_icon()
	make_terminal()

// ─────────────────────────────────────────────────────────────────────────────
// Examine
// ─────────────────────────────────────────────────────────────────────────────

/obj/machinery/power/apc/examine(mob/user)
	. = ..()
	if(Adjacent(user))
		if(stat & BROKEN)
			. += "This APC is broken."
		else if(opened)
			if(has_electronics && terminal)
				. += "The cover is [opened == 2 ? "removed" : "open"] and [cell ? "a power cell is installed" : "the power cell is missing"]."
			else if(!has_electronics && terminal)
				. += "The frame is wired, but the electronics are missing."
			else if(has_electronics && !terminal)
				. += "The electronics are installed, but not wired."
			else
				. += "It's just an empty metal frame."
		else
			if(wiresexposed)
				. += "The cover is closed and the wires are exposed."
			else if((locked && emagged) || hacker)
				. += "The cover is closed, but the panel is unresponsive."
			else if(!locked && emagged)
				. += "The cover is closed, but the panel is flashing an error."
			else
				. += "The cover is closed."

// ─────────────────────────────────────────────────────────────────────────────
// Icon rendering — all visual logic delegated to icon_renderer
// ─────────────────────────────────────────────────────────────────────────────

// update_icon() — called by interactions; delegates to the renderer.
/obj/machinery/power/apc/update_icon()
	if(icon_renderer)
		icon_renderer.apply(src)

// queue_icon_update() — deferred update used during process() to rate-limit
// icon refreshes.
/obj/machinery/power/apc/proc/queue_icon_update()
	if(!updating_icon)
		updating_icon = 1
		spawn(APC_UPDATE_ICON_COOLDOWN)
			if(icon_renderer)
				icon_renderer.apply(src)
			updating_icon = 0

// Legacy check_updates() — retained because wires.dm or other systems may call
// it directly.  Returns 0 if no change, 1 if icon_state changed, 2 if overlays
// changed, 3 if both.
/obj/machinery/power/apc/proc/check_updates()
	if(!icon_renderer)
		return 0
	// Force the renderer to recompute; capture what changed.
	var/old_state   = icon_renderer.last_update_state
	var/old_overlay = icon_renderer.last_update_overlay

	// We use the renderer's internal computation to derive state/overlay bits
	// the same way the renderer would.  We don't apply—just check.
	var/new_state   = icon_renderer._compute_state(src)
	var/new_overlay = icon_renderer._compute_overlay(src, new_state)

	var/result = 0
	if(old_state != new_state)
		result |= 1
	if(old_overlay != new_overlay)
		result |= 2
	return result

// ─────────────────────────────────────────────────────────────────────────────
// Interaction — attackby / attack_hand / emag / etc.
// ─────────────────────────────────────────────────────────────────────────────

/obj/machinery/power/apc/crowbar_act(mob/user, obj/item/tool)
	wake_for_power_dependency()
	add_fingerprint(user)
	if(opened)
		if(has_electronics == APC_HAS_ELECTRONICS_WIRED)
			if(terminal)
				to_chat(user, span_warning("Disconnect the wires first."))
				return ITEM_INTERACT_BLOCKING
			if(use_tool(user, tool, src, delay = 5 SECONDS, volume = 50, message_self = "You begin to remove the power control board...") && has_electronics == APC_HAS_ELECTRONICS_WIRED)
				has_electronics = APC_HAS_ELECTRONICS_NONE
				if(stat & BROKEN)
					user.visible_message(span_warning("[user.name] has broken the charred power control board inside [name]!"), span_notice("You broke the charred power control board and remove the remains."), "You hear a crack!")
				else
					user.visible_message(span_warning("[user.name] has removed the power control board from [name]!"), span_notice("You remove the power control board."))
					new /obj/item/module/power_control(loc)
		else if(opened != 2)
			opened = 0
			update_icon()
		return ITEM_INTERACT_SUCCESS
	if(stat & BROKEN)
		return ITEM_INTERACT_BLOCKING
	var/remaining_power = cell ? cell.percent() : 0
	if(coverlocked && !(stat & MAINT) && remaining_power > 15)
		to_chat(user, span_warning("The cover is locked and cannot be opened."))
		return ITEM_INTERACT_BLOCKING
	opened = 1
	update_icon()
	return ITEM_INTERACT_SUCCESS

/obj/machinery/power/apc/screwdriver_act(mob/user, obj/item/tool)
	wake_for_power_dependency()
	add_fingerprint(user)
	if(opened)
		if(cell)
			to_chat(user, span_warning("Remove the power cell first."))
			return ITEM_INTERACT_BLOCKING
		if(has_electronics == APC_HAS_ELECTRONICS_WIRED && terminal)
			has_electronics = APC_HAS_ELECTRONICS_SECURED
			stat &= ~MAINT
			to_chat(user, "You screw the circuit electronics into place.")
		else if(has_electronics == APC_HAS_ELECTRONICS_SECURED)
			has_electronics = APC_HAS_ELECTRONICS_WIRED
			stat |= MAINT
			to_chat(user, "You unfasten the electronics.")
		else
			to_chat(user, span_warning("There is nothing to secure."))
			return ITEM_INTERACT_BLOCKING
	else
		wiresexposed = !wiresexposed
		to_chat(user, "The wires have been [wiresexposed ? "exposed" : "unexposed"].")
	playsound(src, tool.usesound, 50, TRUE)
	update_icon()
	return ITEM_INTERACT_SUCCESS

/obj/machinery/power/apc/wirecutter_act(mob/user, obj/item/tool)
	wake_for_power_dependency()
	add_fingerprint(user)
	if(!terminal || !opened || has_electronics == APC_HAS_ELECTRONICS_SECURED)
		if(!opened && wiresexposed)
			return attack_hand(user) ? ITEM_INTERACT_SUCCESS : ITEM_INTERACT_BLOCKING
		return ITEM_INTERACT_BLOCKING
	var/turf/floor = loc
	if(floor && !floor.is_plating())
		to_chat(user, span_warning("You must remove the floor plating in front of the APC first."))
		return ITEM_INTERACT_BLOCKING
	playsound(src, 'sound/items/Deconstruct.ogg', 50, TRUE)
	if(use_tool(user, tool, src, delay = 5 SECONDS, volume = 0, message_self = "You begin to cut the cables...", message_others = "[user.name] starts dismantling the [src]'s power terminal.") && terminal && opened && has_electronics != APC_HAS_ELECTRONICS_SECURED)
		if(prob(50) && electrocute_mob(user, terminal.powernet, terminal))
			var/datum/effect/effect/system/spark_spread/sparks = new
			sparks.set_up(5, 1, src)
			sparks.start()
			if(user.get_stunned())
				return ITEM_INTERACT_SUCCESS
		new /obj/item/stack/cable_coil(loc, 10)
		to_chat(user, span_notice("You cut the cables and dismantle the power terminal."))
		qdel(terminal)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/power/apc/welder_act(mob/user, obj/item/tool)
	wake_for_power_dependency()
	add_fingerprint(user)
	if(!opened || has_electronics != APC_HAS_ELECTRONICS_NONE || terminal)
		return ..()
	if(!use_tool(user, tool, src, delay = 5 SECONDS, quality = TOOL_WELDER, amount = 3, volume = 25, \
			message_self = "You start welding the APC frame...", message_others = "[user.name] begins cutting apart [src] with [tool]."))
		return ITEM_INTERACT_SUCCESS
	if(emagged || (stat & BROKEN) || opened == 2)
		new /obj/item/stack/material/steel(loc)
		user.visible_message(span_warning("[src] has been cut apart by [user.name] with [tool]."), span_notice("You disassembled the broken APC frame."), "You hear welding.")
	else
		new /obj/item/frame/apc(loc)
		user.visible_message(span_warning("[src] has been cut from the wall by [user.name] with [tool]."), span_notice("You cut the APC frame from the wall."), "You hear welding.")
	qdel(src)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/power/apc/multitool_act(mob/user, obj/item/tool)
	wake_for_power_dependency()
	add_fingerprint(user)
	if(!opened && wiresexposed)
		return attack_hand(user) ? ITEM_INTERACT_SUCCESS : ITEM_INTERACT_BLOCKING
	if(!opened || !(hacker || emagged))
		return ITEM_INTERACT_BLOCKING
	if(cell)
		to_chat(user, span_warning("You need to remove the power cell first."))
		return ITEM_INTERACT_BLOCKING
	user.visible_message(span_warning("[user.name] connects [tool] to the APC and begins resetting it."), "You begin resetting the APC...")
	if(do_after(user, 5 SECONDS, target = src))
		user.visible_message(span_notice("[user.name] resets the APC with a beep from [tool]."), "You finish resetting the APC.")
		playsound(src, 'sound/machines/chime.ogg', 25, TRUE)
		reboot()
	return ITEM_INTERACT_SUCCESS

/obj/machinery/power/apc/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/apc_use_item,
		/datum/interaction/machine_alt/apc_toggle_lock,
		/datum/interaction/machine_hand/ungated/apc_use,
	)
	..()

/// Old attackby: kept as one effect (never called ..(), so it always fully handled the item).
/datum/interaction/machine_item/apc_use_item
	id = "apc_use_item"
	name = "Use"
	held_type = /obj/item
	effect = /obj/machinery/power/apc/proc/interaction_use_item

/obj/machinery/power/apc/proc/interaction_use_item(mob/user, obj/item/W, datum/interaction/interaction)
	wake_for_power_dependency()
	if(issilicon(user) && get_dist(src, user) > 1)
		attack_hand(user)
		return TRUE
	add_fingerprint(user)
	if(istype(W, /obj/item/cell) && opened)
		if(cell)
			to_chat(user, "The [name] already has a power cell installed.")
			return TRUE
		if(stat & MAINT)
			to_chat(user, span_warning("You need to install the wiring and electronics first."))
			return TRUE
		if(W.w_class != ITEMSIZE_NORMAL)
			to_chat(user, "\The [W] is too [W.w_class < 3 ? "small" : "large"] to work here.")
			return TRUE
		user.drop_item()
		W.forceMove(src)
		cell = W
		user.visible_message(\
			span_warning("[user.name] has inserted a power cell into [name]!"),\
			span_notice("You insert the power cell."))
		power_sync()
		chargecount = 0
		update_icon()
	else if(istype(W, /obj/item/card/id) || istype(W, /obj/item/pda))
		togglelock(user)
	else if(istype(W, /obj/item/stack/cable_coil) && !terminal && opened && has_electronics != APC_HAS_ELECTRONICS_SECURED)
		var/turf/T = loc
		if(istype(T) && !T.is_plating())
			to_chat(user, span_warning("You must remove the floor plating in front of the APC first."))
			return TRUE
		var/obj/item/stack/cable_coil/C = W
		if(C.get_amount() < 10)
			to_chat(user, span_warning("You need ten lengths of cable for that."))
			return TRUE
		user.visible_message(span_warning("[user.name] adds cables to the APC frame."), \
			"You start adding cables to the APC frame...")
		playsound(src, 'sound/items/Deconstruct.ogg', 50, 1)
		if(do_after(user, 2 SECONDS, target = src))
			if(C.get_amount() >= 10 && !terminal && opened && has_electronics != APC_HAS_ELECTRONICS_SECURED)
				var/obj/structure/cable/N = T.get_cable_node()
				if(prob(50) && electrocute_mob(user, N, N))
					var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
					s.set_up(5, 1, src)
					s.start()
					if(user.get_stunned())
						return TRUE
				C.use(10)
				user.visible_message(\
					span_warning("[user.name] has added cables to the APC frame!"),\
					"You add cables to the APC frame.")
				make_terminal()
				terminal.connect_to_network()
	else if(istype(W, /obj/item/module/power_control) && opened && has_electronics == APC_HAS_ELECTRONICS_NONE && !((stat & BROKEN)))
		user.visible_message(span_warning("[user.name] inserts the power control board into [src]."), \
			"You start to insert the power control board into the frame...")
		playsound(src, 'sound/items/Deconstruct.ogg', 50, 1)
		if(do_after(user, 1 SECOND, target = src))
			if(has_electronics == APC_HAS_ELECTRONICS_NONE)
				has_electronics = APC_HAS_ELECTRONICS_WIRED
				reboot()
				to_chat(user, span_notice("You place the power control board inside the frame."))
				qdel(W)
	else if(istype(W, /obj/item/module/power_control) && opened && has_electronics == APC_HAS_ELECTRONICS_NONE && (stat & BROKEN))
		to_chat(user, span_warning("The [src] is too broken for that. Repair it first."))
		return TRUE
	else if(opened && ((stat & BROKEN) || hacker || emagged))
		if(istype(W, /obj/item/frame/apc) && (stat & BROKEN))
			if(cell)
				to_chat(user, span_warning("You need to remove the power cell first."))
				return TRUE
			user.visible_message(span_warning("[user.name] begins replacing the damaged APC cover with a new one."),\
				"You begin to replace the damaged APC cover...")
			if(do_after(user, 5 SECONDS, target = src))
				user.visible_message(span_notice("[user.name] has replaced the damaged APC cover with a new one."),\
					"You replace the damaged APC cover with a new one.")
				qdel(W)
				atom_fix()
				reboot()
				if(opened == 2)
					opened = 1
				update_icon()
	else
		if((stat & BROKEN) \
				&& !opened \
				&& W.force >= 5 \
				&& W.w_class >= ITEMSIZE_SMALL)
			user.visible_message(span_danger("The [name] has been hit with the [W.name] by [user.name]!"), \
				span_danger("You hit the [name] with your [W.name]!"), \
				"You hear a bang!")
			if(prob(20))
				opened = 2
				user.visible_message(span_danger("The APC cover was knocked down with the [W.name] by [user.name]!"), \
					span_danger("You knock down the APC cover with your [W.name]!"), \
					"You hear a bang!")
				update_icon()
		else
			if(istype(user, /mob/living/silicon))
				attack_hand(user)
				return TRUE
			if(!opened && wiresexposed && istype(W, /obj/item/assembly/signaler))
				attack_hand(user)
				return TRUE
			to_chat(user, span_notice("The [name] looks too sturdy to bash open with \the [W.name]."))
	return TRUE

/obj/machinery/power/apc/proc/togglelock(mob/user)
	if(emagged)
		to_chat(user, "The panel is unresponsive.")
	else if(opened)
		to_chat(user, "You must close the cover to swipe an ID card.")
	else if(wiresexposed)
		to_chat(user, "You must close the wire panel.")
	else if(stat & (BROKEN | MAINT))
		to_chat(user, "Nothing happens.")
	else if(hacker)
		to_chat(user, span_warning("Access denied."))
	else
		if(allowed(user) && !wires.is_cut(WIRE_IDSCAN))
			locked = !locked
			to_chat(user, "You [locked ? "lock" : "unlock"] the APC interface.")
			update_icon()
		else
			to_chat(user, span_warning("Access denied."))

/// Old click_alt fell through (no return) to the loot panel afterwards.
/datum/interaction/machine_alt/apc_toggle_lock
	id = "apc_toggle_lock"
	name = "Toggle lock"
	consumes_input = FALSE
	effect = /obj/machinery/power/apc/proc/interaction_toggle_lock

/obj/machinery/power/apc/proc/interaction_toggle_lock(mob/user, obj/item/held, datum/interaction/interaction)
	togglelock(user)
	return TRUE

/obj/machinery/power/apc/emag_act(remaining_charges, mob/user)
	if(!(emagged || hacker))
		if(opened)
			to_chat(user, "You must close the cover to do that.")
		else if(wiresexposed)
			to_chat(user, "You must close the wire panel first.")
		else if(stat & (BROKEN | MAINT))
			to_chat(user, "The [src] isn't working.")
		else
			flick("apc-spark", src)
			if(do_after(user, 6, target = src))
				emagged = 1
				locked = 0
				to_chat(user, span_notice("You emag the APC interface."))
				update_icon()
				return 1

/obj/machinery/power/apc/blob_act()
	wires.cut_all()
	wiresexposed = TRUE
	update_icon()

/// Old attack_hand (never called ..()).
/datum/interaction/machine_hand/ungated/apc_use
	id = "apc_use"
	name = "Use"
	effect = /obj/machinery/power/apc/proc/interaction_use

/obj/machinery/power/apc/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(!user)
		return TRUE
	add_fingerprint(user)

	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		if(H.species.can_shred(H, FALSE, 14))
			user.setClickCooldown(user.get_attack_speed())
			user.visible_message(span_warning("[user.name] slashes at the [name]!"), span_notice("You slash at the [name]!"))
			playsound(src, 'sound/weapons/slash.ogg', 100, 1)
			add_hiddenprint(H)
			if(beenhit >= pick(3, 4) && !wiresexposed)
				wiresexposed = TRUE
				update_icon()
				visible_message(span_warning("The [name]'s cover flies open, exposing the wires!"))
			else if(wiresexposed && wires.cut_all())
				update_icon()
				visible_message(span_warning("The [name]'s wires are shredded!"))
			else
				beenhit += 1
			return TRUE

	if(usr == user && opened && (!issilicon(user)))
		if(cell)
			user.put_in_hands(cell)
			cell.add_fingerprint(user)
			cell.update_icon()
			cell = null
			user.visible_message(span_warning("[user.name] removes the power cell from [name]!"),\
				span_notice("You remove the power cell."))
			charging = 0
			power_sync()
			update_icon()
		return TRUE
	if(stat & (BROKEN | MAINT))
		return TRUE
	interact(user)
	return TRUE

/obj/machinery/power/apc/attack_ghost(mob/user)
	if(panel_open)
		return wires.Interact(user)
	return tgui_interact(user)

/obj/machinery/power/apc/interact(mob/user)
	if(!user)
		return
	if(wiresexposed && !isAI(user))
		wires.Interact(user)
		return
	return tgui_interact(user)

// ─────────────────────────────────────────────────────────────────────────────
// TGUI
// ─────────────────────────────────────────────────────────────────────────────

/obj/machinery/power/apc/tgui_interact(mob/user, datum/tgui/ui = null)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "APC", name)
		ui.open()

/obj/machinery/power/apc/tgui_data(mob/user)
	var/list/data = list(
		"locked"          = locked,
		"normallyLocked"  = locked,
		"emagged"         = emagged,
		"isOperating"     = operating,
		"externalPower"   = main_status,
		"powerCellStatus" = cell ? cell.percent() : 0,
		"chargeMode"      = chargemode,
		"chargingStatus"  = charging,
		"totalLoad"       = round(lastused_total),
		"totalCharging"   = round(lastused_charging),
		"failTime"        = failure_until > world.time ? CEILING((failure_until - world.time) / 10, 1) : 0,
		"gridCheck"       = grid_check,
		"coverLocked"     = coverlocked,
		"siliconUser"     = siliconaccess(user) || (isobserver(user) && is_admin(user)),
		"emergencyLights" = !emergency_lights,
		"nightshiftLights"  = nightshift_lights,
		"nightshiftSetting" = nightshift_setting,
		"powerChannels" = list(
			list(
				"title"       = "Equipment",
				"powerLoad"   = lastused_equip,
				"status"      = equipment,
				"topicParams" = list(
					"auto" = list("eqp" = 3),
					"on"   = list("eqp" = 2),
					"off"  = list("eqp" = 1)
				)
			),
			list(
				"title"       = "Lighting",
				"powerLoad"   = round(lastused_light),
				"status"      = lighting,
				"topicParams" = list(
					"auto" = list("lgt" = 3),
					"on"   = list("lgt" = 2),
					"off"  = list("lgt" = 1)
				)
			),
			list(
				"title"       = "Environment",
				"powerLoad"   = round(lastused_environ),
				"status"      = environ,
				"topicParams" = list(
					"auto" = list("env" = 3),
					"on"   = list("env" = 2),
					"off"  = list("env" = 1)
				)
			)
		)
	)
	return data

/obj/machinery/power/apc/proc/report()
	return "[area.name] : [equipment]/[lighting]/[environ] ([lastused_equip+lastused_light+lastused_environ]) : [cell ? cell.percent() : "N/C"] ([charging])"

// update() — send settings to Rust and push channel state to the area.
/obj/machinery/power/apc/proc/update()
	power_sync()
	apply_area_power()

/// Pushes the channel state to the area; fires area.power_change() (the
/// machinery power signals) only when a channel changed.
/obj/machinery/power/apc/proc/apply_area_power()
	if(!area)
		return
	var/new_power_light = FALSE
	var/new_power_equip = FALSE
	var/new_power_environ = FALSE
	if(operating && !shorted && !grid_check && !failure_timer)
		new_power_light = (lighting >= POWERCHAN_ON)
		new_power_equip = (equipment >= POWERCHAN_ON)
		new_power_environ = (environ >= POWERCHAN_ON)
	if(area.power_light == new_power_light && area.power_equip == new_power_equip && area.power_environ == new_power_environ)
		return
	area.power_light = new_power_light
	area.power_equip = new_power_equip
	area.power_environ = new_power_environ
	area.power_change()
	contract_power_revision++
	var/powered_channels = new_power_light + new_power_equip + new_power_environ
	if(SScontracts)
		emit_contract_event(CONTRACT_EVENT_POWER_SERVICE_CHANGED, list(
			"department" = DEPARTMENT_ENGINEERING,
			"fact_id" = "power-service:[REF(src)]",
			"fact_revision" = contract_power_revision,
			"service_id" = REF(src),
			"operational" = powered_channels == 3,
			"metrics" = list(
				"powered_channels" = powered_channels,
				"cell_percent" = cell ? cell.percent() : 0,
				"load" = lastused_total,
			),
			"detail" = "[area] electrical service reports [powered_channels]/3 powered channels.",
		), "power-service:[REF(src)]:[contract_power_revision]", src)
/obj/machinery/power/apc/proc/can_use(mob/user, loud = 0)
	if(!user.client)
		return 0
	if(isobserver(user) && is_admin(user))
		return 1
	if(user.stat)
		return 0
	if(inoperable())
		return 0
	if(!user.IsAdvancedToolUser())
		return 0
	if(user.restrained())
		to_chat(user, span_warning("Your hands must be free to use [src]."))
		return 0
	if(user.lying)
		to_chat(user, span_warning("You must stand to use [src]!"))
		return 0
	autoflag = 5
	if(istype(user, /mob/living/silicon))
		var/permit = 0
		var/mob/living/silicon/ai/AI = user
		var/mob/living/silicon/robot/robot = user
		if(hacker)
			if(hacker == AI)
				permit = 1
			else if(istype(robot) && robot.connected_ai && robot.connected_ai == hacker)
				permit = 1
		if(aidisabled && !permit)
			if(!loud)
				to_chat(user, span_danger("\The AI control for [src] has been disabled!"))
			return 0
	else
		if(!in_range(src, user) || !istype(loc, /turf))
			return 0
	var/mob/living/carbon/human/H = user
	if(istype(H) && prob(H.injury_load(INJURY_CATEGORY_NEURAL)))
		to_chat(user, span_danger("You momentarily forget how to use [src]."))
		return 0
	return 1

/obj/machinery/power/apc/tgui_act(action, params, datum/tgui/ui)
	wake_for_power_dependency()
	if(..() || !can_use(ui.user, TRUE))
		return TRUE

	var/locked_exception = FALSE
	if(siliconaccess(ui.user) || action == "nightshift")
		locked_exception = TRUE
	if(isobserver(ui.user))
		var/mob/observer/dead/D = ui.user
		if(D.can_admin_interact())
			locked_exception = TRUE

	if(locked && !locked_exception)
		return

	. = TRUE
	switch(action)
		if("lock")
			if(locked_exception)
				if(emagged || (stat & (BROKEN | MAINT)))
					to_chat(ui.user, "The APC does not respond to the command.")
					return
				locked = !locked
				update_icon()
		if("cover")
			coverlocked = !coverlocked
		if("breaker")
			toggle_breaker()
		if("nightshift")
			if(last_nightshift_switch > world.time - 1 SECOND)
				to_chat(ui.user, span_warning("[src]'s night lighting circuit breaker is still cycling!"))
				return 0
			var/requested_nightshift = text2num("[params["nightshift"]]")
			if(requested_nightshift < NIGHTSHIFT_AUTO || requested_nightshift > NIGHTSHIFT_ALWAYS)
				return 0
			if(requested_nightshift == nightshift_setting)
				return 0
			last_nightshift_switch = world.time
			nightshift_setting = requested_nightshift
			update_nightshift()
		if("charge")
			chargemode = !chargemode
			if(!chargemode)
				charging = 0
				update_icon()
			power_sync()
		if("channel")
			if(params["eqp"])
				equipment = setsubsystem(text2num(params["eqp"]))
			else if(params["lgt"])
				lighting = setsubsystem(text2num(params["lgt"]))
			else if(params["env"])
				environ = setsubsystem(text2num(params["env"]))
			update_icon()
			update()
		if("reboot")
			failure_timer = 0
			failure_until = 0
			if(failure_wake_timer)
				deltimer(failure_wake_timer)
				failure_wake_timer = null
			update_icon()
			update()
		if("emergency_lighting")
			emergency_lights = !emergency_lights
			for(var/obj/machinery/light/L in area)
				if(!initial(L.no_emergency))
					L.no_emergency = emergency_lights
					INVOKE_ASYNC(L, TYPE_PROC_REF(/obj/machinery/light, update), FALSE)
				CHECK_TICK
		if("overload")
			if(locked_exception)
				overload_lighting()

/obj/machinery/power/apc/proc/toggle_breaker()
	wake_for_power_dependency()
	operating = !operating
	update()
	update_icon()

/obj/machinery/power/apc/surplus()
	if(terminal)
		return terminal.surplus()
	else
		return 0

/obj/machinery/power/apc/proc/last_surplus()
	if(terminal && terminal.powernet)
		return terminal.powernet.last_surplus()
	else
		return 0

/obj/machinery/power/apc/draw_power(amount)
	if(terminal && terminal.powernet)
		return terminal.powernet.draw_power(amount, terminal)
	return 0

/obj/machinery/power/apc/avail()
	if(terminal)
		return terminal.avail()
	else
		return 0

// ─────────────────────────────────────────────────────────────────────────────
// Main process() — the distributor runs in Rust
// ─────────────────────────────────────────────────────────────────────────────

/// APCs do not poll: Rust runs the distributor. A wake only resends settings.
/obj/machinery/power/apc/process()
	power_sync()
	return PROCESS_KILL

/obj/machinery/power/apc/proc/wake_after_failure()
	failure_wake_timer = null
	if(failure_until > world.time)
		failure_wake_timer = addtimer(CALLBACK(src, PROC_REF(wake_after_failure)), failure_until - world.time, TIMER_STOPPABLE)
		return
	failure_timer = 0
	failure_until = 0
	queue_icon_update()
	update()

// ─────────────────────────────────────────────────────────────────────────────
// Legacy passthrough procs — kept for external call-site compatibility
// ─────────────────────────────────────────────────────────────────────────────

/// autoset() — the channel state machine (Rust runs the same table).
/// on: 0 = force off, 1 = allow on, 2 = auto-off.
/obj/machinery/power/apc/proc/autoset(cur_state, on)
	switch(cur_state)
		if(POWERCHAN_OFF_AUTO)
			if(on == 1)
				return POWERCHAN_ON_AUTO
		if(POWERCHAN_ON)
			if(on == 0)
				return POWERCHAN_OFF
		if(POWERCHAN_ON_AUTO)
			if(on == 0 || on == 2)
				return POWERCHAN_OFF_AUTO
	return cur_state

/// setsubsystem() — maps a UI value to a valid POWERCHAN_* constant.
/obj/machinery/power/apc/proc/setsubsystem(val)
	if(cell && cell.charge > 0)
		return (val == 1) ? POWERCHAN_OFF : val
	else if(val == POWERCHAN_ON_AUTO)
		return POWERCHAN_OFF_AUTO
	else
		return POWERCHAN_OFF

/// Channel settings changed outside the UI (wires, hacking): send them.
/obj/machinery/power/apc/proc/update_channels()
	power_sync()

// ─────────────────────────────────────────────────────────────────────────────
// Damage / destruction
// ─────────────────────────────────────────────────────────────────────────────

/obj/machinery/power/apc/emp_act(severity, recursive)
	wake_for_power_dependency()
	. = ..()
	if(. & EMP_PROTECT_SELF)
		return
	if(is_critical)
		energy_fail(rand(240, 360) / severity / CRITICAL_APC_EMP_PROTECTION)
		severity = severity + 2
	else
		energy_fail(rand(240, 360) / severity)
		severity = severity + 1
	update_icon()

/obj/machinery/power/apc/ex_act(severity)
	wake_for_power_dependency()
	return ..()

/obj/machinery/power/apc/explosion_contents_severity(severity)
	return severity

/obj/machinery/power/apc/atom_break(damage_flag)
	. = ..()
	if(!.)
		return
	visible_message(span_warning("[src]'s screen flickers suddenly, then explodes in a rain of sparks and small debris!"))
	operating = 0
	update()

/obj/machinery/power/apc/disconnect_terminal(obj/machinery/power/terminal/term)
	if(terminal)
		terminal.master = null
		terminal = null
	wake_for_power_dependency()

/obj/machinery/power/apc/proc/overload_lighting(chance = 100)
	if(!operating || shorted || grid_check)
		return
	if(cell && cell.charge >= 20)
		cell.use(20)
		spawn(0)
			for(var/obj/machinery/light/L in area)
				if(prob(chance))
					L.on = 1
					L.broken()
				sleep(1)

// ─────────────────────────────────────────────────────────────────────────────
// AI malfunction
// ─────────────────────────────────────────────────────────────────────────────

/obj/machinery/power/apc/proc/ai_hack(mob/living/silicon/ai/A = null)
	if(!A || !A.hacked_apcs || hacker || aidisabled || A.stat == DEAD)
		return 0
	hacker = A
	A.hacked_apcs += src
	locked = 1
	update_icon()
	return 1

// ─────────────────────────────────────────────────────────────────────────────
// Reboot
// ─────────────────────────────────────────────────────────────────────────────

/obj/machinery/power/apc/proc/reboot()
	// Reset distribution state.
	lighting = POWERCHAN_ON_AUTO
	equipment = POWERCHAN_ON_AUTO
	environ = POWERCHAN_ON_AUTO
	charging = 0
	chargecount = 0
	autoflag = 0
	longtermpower = 10
	lastused_light = 0
	lastused_equip = 0
	lastused_environ = 0
	lastused_charging = 0
	lastused_total = 0
	main_status = APC_EXTERNAL_POWER_NOTCONNECTED

	// Breaker off; chargemode in default state; all channels on auto.
	operating   = 0
	chargemode  = 1
	failure_timer = 0
	failure_until = 0
	if(failure_wake_timer)
		deltimer(failure_wake_timer)
		failure_wake_timer = null
	GLOB.power_alarm.clearAlarm(loc, src)

	// Clear malf AI ownership.
	if(hacker && hacker.hacked_apcs && (src in hacker.hacked_apcs))
		hacker.hacked_apcs -= src
	hacker = null
	emagged = initial(emagged)

	// Force icon renderer to recompute from scratch.
	if(icon_renderer)
		icon_renderer.force_apply(src)
	update()

// ─────────────────────────────────────────────────────────────────────────────
// Overload / grid check / nightshift / area update
// ─────────────────────────────────────────────────────────────────────────────

/obj/machinery/power/apc/overload(obj/machinery/power/source)
	if(is_critical)
		return
	if(prob(30)) return
	if(prob(40)) overload_lighting()
	if(prob(40))
		for(var/obj/machinery/light/L in area)
			L.flicker(rand(20, 30))
	if(prob(25))
		emagged = 1
		locked = 0
		update_icon()
	if(prob(25))
		if(cell)
			cell.corrupt()
	if(prob(10))
		for(var/obj/machinery/computer/comp in area)
			comp.ex_act(3)
	if(prob(5))
		atom_break()

/obj/machinery/power/apc/do_grid_check()
	if(is_critical)
		return
	grid_check = TRUE
	spawn(15 MINUTES)
		if(src && grid_check == TRUE)
			grid_check = FALSE

/obj/machinery/power/apc/proc/set_nightshift(on, automated)
	set waitfor = FALSE
	if(automated && istype(area, /area/shuttle))
		return
	nightshift_lights = on
	update_nightshift()

/obj/machinery/power/apc/proc/update_nightshift()
	var/new_state = nightshift_lights
	switch(nightshift_setting)
		if(NIGHTSHIFT_NEVER)  new_state = FALSE
		if(NIGHTSHIFT_ALWAYS) new_state = TRUE
	for(var/obj/machinery/light/L in area)
		L.nightshift_mode(new_state)
		CHECK_TICK

/obj/machinery/power/apc/proc/update_area()
	var/area/NA = get_area(src)
	if(NA != area)
		if(area.apc == src)
			area.apc = null
		NA.apc = src
		area = NA
		name = "[area.name] APC"
	update()

/obj/machinery/power/apc/get_cell()
	return cell

// All APC defines are declared in code/__defines/apc.dm and are not #undef'd
// here because they are shared with apc_icon_renderer.

