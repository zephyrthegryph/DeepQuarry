GLOBAL_LIST_EMPTY(apcs)

// the Area Power Controller (APC), formerly Power Distribution Unit (PDU)
// one per area, needs wire connection to power network through a terminal
//
// All APC #defines live in code/__defines/apc.dm so they are available to the
// delegate datums (apc_power_distributor, apc_icon_renderer) regardless of
// include order.

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
	var/force_update = 0
	var/updating_icon = 0
	var/alarms_hidden = FALSE       // if TRUE, power alarms from this APC are hidden on consoles
	var/nightshift_lights = FALSE
	var/nightshift_setting = NIGHTSHIFT_AUTO
	var/last_nightshift_switch = 0

	// ── delegate datums ──────────────────────────────────────────────────────
	/// Manages channel state-machine, cell charging, and load tracking.
	var/datum/apc_power_distributor/power_distributor = null
	/// Handles icon_state, overlays, and light.
	var/datum/apc_icon_renderer/icon_renderer = null

	// ── channel state passthrough (read from power_distributor) ──────────────
	// These vars exist so existing call sites and TGUI work unchanged.
	// They are always kept in sync with the distributor every process() tick.
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
	/// Legacy icon-diff state retained for queue_icon_update().
	var/update_state   = -1
	var/update_overlay = -1

// ─────────────────────────────────────────────────────────────────────────────
// Powernet integration
// ─────────────────────────────────────────────────────────────────────────────

/obj/machinery/power/apc/connect_to_network()
	// Override: APC does not directly connect to the network; it goes through a terminal.
	if(!terminal)
		make_terminal()
	if(terminal)
		terminal.connect_to_network()

/obj/machinery/power/apc/drain_power(drain_check, surge, amount = 0)
	if(drain_check)
		return 1

	// Fully draining an APC cell would break charging; reset charging state.
	if(power_distributor)
		power_distributor.charging = 0
		charging = 0

	var/drained_energy = 0

	// Draw from the grid first (like draining from a cable).
	if(terminal && terminal.powernet)
		terminal.powernet.trigger_warning()
		drained_energy += terminal.powernet.draw_power(amount)

	// Grid rarely gives the full amount; draw the shortfall from the cell.
	if((drained_energy < amount) && cell)
		drained_energy += cell.drain_power(0, 0, (amount - drained_energy))

	return drained_energy

// ─────────────────────────────────────────────────────────────────────────────
// Lifecycle
// ─────────────────────────────────────────────────────────────────────────────

/obj/machinery/power/apc/Initialize(mapload, ndir, building)
	. = ..()
	set_wires(new /datum/wires/apc(src))
	GLOB.apcs += src

	power_distributor = new /datum/apc_power_distributor(src)
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
	GLOB.apcs -= src
	update()

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
	QDEL_NULL(power_distributor)
	QDEL_NULL(icon_renderer)

	return ..()

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
	failure_timer = max(failure_timer, round(duration))

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

// update_icon() — called by interactions; syncs APC vars from distributor then
// delegates to the renderer.
/obj/machinery/power/apc/update_icon()
	_sync_from_distributor()
	if(icon_renderer)
		icon_renderer.apply(src)

// queue_icon_update() — deferred update used during process() to rate-limit
// icon refreshes.
/obj/machinery/power/apc/proc/queue_icon_update()
	if(!updating_icon)
		updating_icon = 1
		spawn(APC_UPDATE_ICON_COOLDOWN)
			_sync_from_distributor()
			if(icon_renderer)
				icon_renderer.apply(src)
			updating_icon = 0

// _sync_from_distributor() — copies distributor state into APC vars so that
// icon_renderer, TGUI, and any direct var-readers see consistent values.
/obj/machinery/power/apc/proc/_sync_from_distributor()
	if(!power_distributor)
		return
	lighting    = power_distributor.lighting
	equipment   = power_distributor.equipment
	environ     = power_distributor.environ
	charging    = power_distributor.charging
	chargemode  = power_distributor.chargemode
	chargecount = power_distributor.chargecount
	autoflag    = power_distributor.autoflag
	longtermpower = power_distributor.longtermpower
	lastused_light    = power_distributor.lastused_light
	lastused_equip    = power_distributor.lastused_equip
	lastused_environ  = power_distributor.lastused_environ
	lastused_charging = power_distributor.lastused_charging
	lastused_total    = power_distributor.lastused_total
	main_status = power_distributor.main_status

// _sync_to_distributor() — writes APC vars back into the distributor.
// Called before any proc that reads from the distributor to ensure coherence
// when direct APC var mutation happens (e.g. reboot()).
/obj/machinery/power/apc/proc/_sync_to_distributor()
	if(!power_distributor)
		return
	power_distributor.lighting    = lighting
	power_distributor.equipment   = equipment
	power_distributor.environ     = environ
	power_distributor.charging    = charging
	power_distributor.chargemode  = chargemode
	power_distributor.chargecount = chargecount
	power_distributor.autoflag    = autoflag
	power_distributor.longtermpower = longtermpower

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

/obj/machinery/power/apc/attackby(obj/item/W, mob/user)
	if(issilicon(user) && get_dist(src, user) > 1)
		return attack_hand(user)
	add_fingerprint(user)
	if(W.has_tool_quality(TOOL_CROWBAR) && opened)
		if(has_electronics == APC_HAS_ELECTRONICS_WIRED)
			if(terminal)
				to_chat(user, span_warning("Disconnect the wires first."))
				return
			playsound(src, W.usesound, 50, 1)
			to_chat(user, "You begin to remove the power control board...")
			if(do_after(user, 5 SECONDS * W.toolspeed, target = src))
				if(has_electronics == APC_HAS_ELECTRONICS_WIRED)
					has_electronics = APC_HAS_ELECTRONICS_NONE
					if(stat & BROKEN)
						user.visible_message(\
							span_warning("[user.name] has broken the charred power control board inside [name]!"),\
							span_notice("You broke the charred power control board and remove the remains."),
							"You hear a crack!")
					else
						user.visible_message(\
							span_warning("[user.name] has removed the power control board from [name]!"),\
							span_notice("You remove the power control board."))
						new /obj/item/module/power_control(loc)
		else if(opened != 2) // cover isn't removed
			opened = 0
			update_icon()
	else if(W.has_tool_quality(TOOL_CROWBAR) && !(stat & BROKEN))
		var/remaining_power = 0
		if(cell)
			remaining_power = cell.percent()
		if(coverlocked && !(stat & MAINT) && remaining_power > 15)
			to_chat(user, span_warning("The cover is locked and cannot be opened."))
			return
		else
			opened = 1
			update_icon()
	else if(istype(W, /obj/item/cell) && opened)
		if(cell)
			to_chat(user, "The [name] already has a power cell installed.")
			return
		if(stat & MAINT)
			to_chat(user, span_warning("You need to install the wiring and electronics first."))
			return
		if(W.w_class != ITEMSIZE_NORMAL)
			to_chat(user, "\The [W] is too [W.w_class < 3 ? "small" : "large"] to work here.")
			return
		user.drop_item()
		W.forceMove(src)
		cell = W
		user.visible_message(\
			span_warning("[user.name] has inserted a power cell into [name]!"),\
			span_notice("You insert the power cell."))
		if(power_distributor)
			power_distributor.chargecount = 0
		chargecount = 0
		update_icon()
	else if(W.has_tool_quality(TOOL_SCREWDRIVER))
		if(opened)
			if(cell)
				to_chat(user, span_warning("Remove the power cell first."))
				return
			else
				if(has_electronics == APC_HAS_ELECTRONICS_WIRED && terminal)
					has_electronics = APC_HAS_ELECTRONICS_SECURED
					stat &= ~MAINT
					playsound(src, W.usesound, 50, 1)
					to_chat(user, "You screw the circuit electronics into place.")
				else if(has_electronics == APC_HAS_ELECTRONICS_SECURED)
					has_electronics = APC_HAS_ELECTRONICS_WIRED
					stat |= MAINT
					playsound(src, W.usesound, 50, 1)
					to_chat(user, "You unfasten the electronics.")
				else
					to_chat(user, span_warning("There is nothing to secure."))
					return
				update_icon()
		else
			wiresexposed = !wiresexposed
			to_chat(user, "The wires have been [wiresexposed ? "exposed" : "unexposed"].")
			playsound(src, W.usesound, 50, 1)
			update_icon()
	else if(istype(W, /obj/item/card/id) || istype(W, /obj/item/pda))
		togglelock(user)
	else if(istype(W, /obj/item/stack/cable_coil) && !terminal && opened && has_electronics != APC_HAS_ELECTRONICS_SECURED)
		var/turf/T = loc
		if(istype(T) && !T.is_plating())
			to_chat(user, span_warning("You must remove the floor plating in front of the APC first."))
			return
		var/obj/item/stack/cable_coil/C = W
		if(C.get_amount() < 10)
			to_chat(user, span_warning("You need ten lengths of cable for that."))
			return
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
					if(user.stunned)
						return
				C.use(10)
				user.visible_message(\
					span_warning("[user.name] has added cables to the APC frame!"),\
					"You add cables to the APC frame.")
				make_terminal()
				terminal.connect_to_network()
	else if(W.has_tool_quality(TOOL_WIRECUTTER) && terminal && opened && has_electronics != APC_HAS_ELECTRONICS_SECURED)
		var/turf/T = loc
		if(istype(T) && !T.is_plating())
			to_chat(user, span_warning("You must remove the floor plating in front of the APC first."))
			return
		user.visible_message(span_warning("[user.name] starts dismantling the [src]'s power terminal."), \
			"You begin to cut the cables...")
		playsound(src, 'sound/items/Deconstruct.ogg', 50, 1)
		if(do_after(user, 5 SECONDS * W.toolspeed, target = src))
			if(terminal && opened && has_electronics != APC_HAS_ELECTRONICS_SECURED)
				if(prob(50) && electrocute_mob(user, terminal.powernet, terminal))
					var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
					s.set_up(5, 1, src)
					s.start()
					if(user.stunned)
						return
				new /obj/item/stack/cable_coil(loc, 10)
				to_chat(user, span_notice("You cut the cables and dismantle the power terminal."))
				qdel(terminal)
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
		return
	else if(W.has_tool_quality(TOOL_WELDER) && opened && has_electronics == APC_HAS_ELECTRONICS_NONE && !terminal)
		var/obj/item/weldingtool/WT = W.get_welder()
		if(WT.get_fuel() < 3)
			to_chat(user, span_warning("You need more welding fuel to complete this task."))
			return
		user.visible_message(span_warning("[user.name] begins cutting apart [src] with the [WT.name]."), \
			"You start welding the APC frame...", \
			"You hear welding.")
		playsound(src, WT.usesound, 25, 1)
		if(do_after(user, 5 SECONDS * WT.toolspeed, target = src))
			if(!src || !WT.remove_fuel(3, user)) return
			if(emagged || (stat & BROKEN) || opened == 2)
				new /obj/item/stack/material/steel(loc)
				user.visible_message(\
					span_warning("[src] has been cut apart by [user.name] with the [WT.name]."),\
					span_notice("You disassembled the broken APC frame."),\
					"You hear welding.")
			else
				new /obj/item/frame/apc(loc)
				user.visible_message(\
					span_warning("[src] has been cut from the wall by [user.name] with the [WT.name]."),\
					span_notice("You cut the APC frame from the wall."),\
					"You hear welding.")
			qdel(src)
			return
	else if(opened && ((stat & BROKEN) || hacker || emagged))
		if(istype(W, /obj/item/frame/apc) && (stat & BROKEN))
			if(cell)
				to_chat(user, span_warning("You need to remove the power cell first."))
				return
			user.visible_message(span_warning("[user.name] begins replacing the damaged APC cover with a new one."),\
				"You begin to replace the damaged APC cover...")
			if(do_after(user, 5 SECONDS, target = src))
				user.visible_message(span_notice("[user.name] has replaced the damaged APC cover with a new one."),\
					"You replace the damaged APC cover with a new one.")
				qdel(W)
				stat &= ~BROKEN
				reboot()
				if(opened == 2)
					opened = 1
				update_icon()
		else if(istype(W, /obj/item/multitool) && (hacker || emagged))
			if(cell)
				to_chat(user, span_warning("You need to remove the power cell first."))
				return
			user.visible_message(span_warning("[user.name] connects their [W.name] to the APC and begins resetting it."),\
				"You begin resetting the APC...")
			if(do_after(user, 5 SECONDS, target = src))
				user.visible_message(span_notice("[user.name] resets the APC with a beep from their [W.name]."),\
					"You finish resetting the APC.")
				playsound(src, 'sound/machines/chime.ogg', 25, 1)
				reboot()
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
				return attack_hand(user)
			if(!opened && wiresexposed && (istype(W, /obj/item/multitool) || W.has_tool_quality(TOOL_WIRECUTTER) || istype(W, /obj/item/assembly/signaler)))
				return attack_hand(user)
			to_chat(user, span_notice("The [name] looks too sturdy to bash open with \the [W.name]."))

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

/obj/machinery/power/apc/click_alt(mob/user)
	..()
	togglelock(user)

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
	if(!wires.is_all_cut())
		wiresexposed = TRUE
		wires.cut_all()
		update_icon()

/obj/machinery/power/apc/attack_hand(mob/user)
	if(!user)
		return
	add_fingerprint(user)

	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		if(H.species.can_shred(H, FALSE, 14))
			user.setClickCooldown(user.get_attack_speed())
			user.visible_message(span_warning("[user.name] slashes at the [name]!"), span_notice("You slash at the [name]!"))
			playsound(src, 'sound/weapons/slash.ogg', 100, 1)
			add_hiddenprint(H)
			var/allcut = wires.is_all_cut()
			if(beenhit >= pick(3, 4) && !wiresexposed)
				wiresexposed = TRUE
				update_icon()
				visible_message(span_warning("The [name]'s cover flies open, exposing the wires!"))
			else if(wiresexposed && allcut == 0)
				wires.cut_all()
				update_icon()
				visible_message(span_warning("The [name]'s wires are shredded!"))
			else
				beenhit += 1
			return

	if(usr == user && opened && (!issilicon(user)))
		if(cell)
			user.put_in_hands(cell)
			cell.add_fingerprint(user)
			cell.update_icon()
			cell = null
			user.visible_message(span_warning("[user.name] removes the power cell from [name]!"),\
				span_notice("You remove the power cell."))
			if(power_distributor)
				power_distributor.charging = 0
			charging = 0
			update_icon()
		return
	if(stat & (BROKEN | MAINT))
		return
	interact(user)

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
	_sync_from_distributor()
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
		"failTime"        = failure_timer * 2,
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

// update() — push channel state to the area and fire power_change().
/obj/machinery/power/apc/proc/update()
	if(operating && !shorted && !grid_check && !failure_timer)
		area.power_light  = (lighting  >= POWERCHAN_ON)
		area.power_equip  = (equipment >= POWERCHAN_ON)
		area.power_environ = (environ   >= POWERCHAN_ON)
	else
		area.power_light  = 0
		area.power_equip  = 0
		area.power_environ = 0
	area.power_change()

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
	if(istype(H) && prob(H.getBrainLoss()))
		to_chat(user, span_danger("You momentarily forget how to use [src]."))
		return 0
	return 1

/obj/machinery/power/apc/tgui_act(action, params, datum/tgui/ui)
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
			if(last_nightshift_switch > world.time - 10 SECONDS)
				to_chat(ui.user, span_warning("[src]'s night lighting circuit breaker is still cycling!"))
				return 0
			last_nightshift_switch = world.time
			nightshift_setting = params["nightshift"]
			update_nightshift()
		if("charge")
			chargemode = !chargemode
			if(power_distributor)
				power_distributor.chargemode = chargemode
			if(!chargemode)
				if(power_distributor)
					power_distributor.charging = 0
				charging = 0
				update_icon()
		if("channel")
			if(power_distributor)
				if(params["eqp"])
					power_distributor.set_channel("eqp", params["eqp"])
					_sync_from_distributor()
					update_icon()
					update()
				else if(params["lgt"])
					power_distributor.set_channel("lgt", params["lgt"])
					_sync_from_distributor()
					update_icon()
					update()
				else if(params["env"])
					power_distributor.set_channel("env", params["env"])
					_sync_from_distributor()
					update_icon()
					update()
		if("reboot")
			failure_timer = 0
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
		return terminal.powernet.draw_power(amount)
	return 0

/obj/machinery/power/apc/avail()
	if(terminal)
		return terminal.avail()
	else
		return 0

// ─────────────────────────────────────────────────────────────────────────────
// Main process() — delegates to power_distributor
// ─────────────────────────────────────────────────────────────────────────────

/obj/machinery/power/apc/process()
	if(!area.requires_power)
		return PROCESS_KILL
	if(stat & (BROKEN | MAINT))
		return
	if(failure_timer)
		update()
		queue_icon_update()
		failure_timer--
		force_update = 1
		return

	if(!power_distributor)
		return

	// Run the distributor's per-tick logic.
	var/changed = power_distributor.tick()

	// Sync results back into APC vars for TGUI and icon rendering.
	_sync_from_distributor()

	if(debug)
		log_world("[src]: Status: [main_status] - Excess: [surplus()] - Last Equip: [lastused_equip] - Last Light: [lastused_light] - Longterm: [longtermpower]")

	// Update icon & area power if anything changed.
	if(changed & 1 || force_update)
		force_update = 0
		queue_icon_update()
		update()
	else if(changed & 2)
		queue_icon_update()

// ─────────────────────────────────────────────────────────────────────────────
// Legacy passthrough procs — kept for external call-site compatibility
// ─────────────────────────────────────────────────────────────────────────────

/// autoset() passthrough — delegates to power_distributor if available.
/obj/machinery/power/apc/proc/autoset(cur_state, on)
	if(power_distributor)
		return power_distributor.autoset(cur_state, on)
	// Fallback if called before distributor is ready (shouldn't happen in normal play).
	switch(cur_state)
		if(POWERCHAN_OFF_AUTO)
			if(on == 1) return POWERCHAN_ON_AUTO
		if(POWERCHAN_ON)
			if(on == 0) return POWERCHAN_OFF
		if(POWERCHAN_ON_AUTO)
			if(on == 0 || on == 2) return POWERCHAN_OFF_AUTO
	return cur_state

/// setsubsystem() passthrough.
/obj/machinery/power/apc/proc/setsubsystem(val)
	if(power_distributor)
		return power_distributor.setsubsystem(val)
	if(cell && cell.charge > 0)
		return (val == 1) ? POWERCHAN_OFF : val
	else if(val == POWERCHAN_ON_AUTO)
		return POWERCHAN_OFF_AUTO
	else
		return POWERCHAN_OFF

/// update_channels() passthrough — called by external code (e.g. wires.dm).
/obj/machinery/power/apc/proc/update_channels()
	if(power_distributor)
		_sync_to_distributor()
		power_distributor._update_channels()
		_sync_from_distributor()

// ─────────────────────────────────────────────────────────────────────────────
// Damage / destruction
// ─────────────────────────────────────────────────────────────────────────────

/obj/machinery/power/apc/emp_act(severity, recursive)
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
	switch(severity)
		if(1)
			if(cell)
				cell.ex_act(1)
			qdel(src)
			return
		if(2)
			if(prob(75))
				set_broken()
				if(cell && prob(50))
					cell.ex_act(2)
		if(3)
			if(prob(50))
				set_broken()
				if(cell && prob(50))
					cell.ex_act(3)
		if(4)
			if(prob(25))
				set_broken()
				if(cell && prob(50))
					cell.ex_act(3)
	return

/obj/machinery/power/apc/disconnect_terminal(obj/machinery/power/terminal/term)
	if(terminal)
		terminal.master = null
		terminal = null

/obj/machinery/power/apc/proc/set_broken()
	spawn(rand(2, 5))
		visible_message(span_warning("[src]'s screen flickers suddenly, then explodes in a rain of sparks and small debris!"))
		stat |= BROKEN
		operating = 0
		update_icon()
		update()

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
	// Reset distribute-side state.
	if(power_distributor)
		power_distributor.reset()
		power_distributor.chargemode = chargemode  // preserve user setting

	// Reset APC-side state (mirrored from distributor where needed).
	_sync_from_distributor()

	// Breaker off; chargemode in default state; all channels on auto.
	operating   = 0
	chargemode  = 1
	if(power_distributor)
		power_distributor.chargemode = 1
	failure_timer = 0
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
		set_broken()

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
		L.update()
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
// here because they are shared with apc_power_distributor and apc_icon_renderer.
