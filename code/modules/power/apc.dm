
// the Area Power Controller (APC), formerly Power Distribution Unit (PDU)
// one per area, needs wire connection to power network through a terminal
//
// All APC #defines live in code/__defines/apc.dm.
//
// M3: the distributor (channels, cell charging, load shedding) runs in Rust
// (verdigris/domains/power/src/apc.rs) every power step. The APC never polls:
// power_sync() sends its settings, and power_poll() applies what Rust
// reports (channels, charging, status, alarm, the cell charge).
//
// DX (doc/rewrite/dx_conventions.md): the APC is built from capabilities. Its cover, wire panel, ID
// lock, cell bay, channels/breaker/night shift and power-system membership are library bundles
// (capabilities() below); its own entries are the frame and electronics steps, the emag, the touch,
// the alt-click lock and the bash. Its look is draw(); its window is tgui_id + tgui_data() + act_*().

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

/obj/machinery/power/apc/angled/wall_mount_orient(offset)
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
	clicksound = SFX_SWITCH
	req_access = list(ACCESS_ENGINE_EQUIP)
	blocks_emissive = EMISSIVE_BLOCK_NONE
	vis_flags = VIS_HIDE // They have an emissive that looks bad in openspace due to their wall-mounted nature
	flags = WALL_ITEM
	integrity_failure = 0.5
	/// The ID lock is engaged by default (maps clear it with cap_state).
	cap_state = CAP_LOCKED
	tgui_id = "APC"

	// ── area/cell wiring ────────────────────────────────────────────────────
	var/tmp/area/area
	var/areastring = null
	var/obj/item/cell/cell
	/// Cap for how fast APC cells charge, as a percentage-per-tick.
	/// 0.0005 means cellcharge is capped to ~0.05% per second.
	var/chargelevel = 0.0005
	var/start_charge = 90           // initial cell charge %
	var/cell_type = /obj/item/cell/apc

	// ── physical state ──────────────────────────────────────────────────────
	// Cover, wire panel, ID lock and emag are capability state (cap_state): cover_is_open(),
	// cover_removed(), panel_is_open(), is_locked(), is_emagged().
	var/shorted = 0
	var/grid_check = FALSE
	/// The cover lock (UI "Cover Lock"): the cover can't be pried open while the cell holds charge.
	var/coverlocked = 1
	var/aidisabled = 0
	var/obj/machinery/power/terminal/terminal = null
	var/mob/living/silicon/ai/hacker = null // Malf AI that has full control of this APC.
	power_region = 0                 // set by connect_to_network() (the APC IS a network node now, step 3)
	var/debug = 0
	var/has_electronics = APC_HAS_ELECTRONICS_NONE
	var/beenhit = 0                 // hit counter, used for Alien claws
	var/emergency_lights = FALSE
	var/is_critical = 0
	/// An EMP / power failure is on (timed_set() ends it: time_left(src, nameof(power_failed))).
	var/power_failed = FALSE
	var/alarms_hidden = FALSE       // if TRUE, power alarms from this APC are hidden on consoles
	var/nightshift_lights = FALSE
	var/nightshift_setting = NIGHTSHIFT_AUTO

	/// The power alarm is raised (as Rust last reported).
	var/power_alarm_raised = FALSE
	/// Power events applied (tests check that a settled APC hears none).
	var/power_event_count = 0

	// ── channel state ────────────────────────────────────────────────────────
	// Rust reports these after every power step; power_sync() sends edits.
	var/lighting  = POWERCHAN_ON_AUTO
	var/equipment = POWERCHAN_ON_AUTO
	var/environ   = POWERCHAN_ON_AUTO
	var/operating = 1
	var/charging    = 0
	var/chargemode  = 1
	var/chargecount = 0
	var/longtermpower = 10
	var/main_status = APC_EXTERNAL_POWER_NOTCONNECTED
	/// Monotonic revision for correction-aware contract power telemetry.
	var/contract_power_revision = 0

APPEARANCE_NONE(/obj/machinery/power/apc) // ALLOW(sys_dx_old_forms): drops the inherited machinery appearance; draw() is the look

/// The machinery appearance watch (stat, ...) and legacy callers reach draw() through this.
/obj/machinery/power/apc/update_icon() // ALLOW(sys_update_icon): bridge while machinery watches call update_icon(): marks the APC so draw() runs
	changed(src)

// ─────────────────────────────────────────────────────────────────────────────
// Capabilities
// ─────────────────────────────────────────────────────────────────────────────

/obj/machinery/power/apc/capabilities()
	. = ..()
	. += wall_machine(board = /obj/item/module/power_control, repair_tool = NONE)
	. += maintenance_hatch(/datum/wires/apc, access = ACCESS_ENGINE_EQUIP, cover_locked_while = PROC_REF(cover_holds), panel_needs_cover_closed = TRUE)
	. += cell_bay(nameof(cell))
	. += power_channels()
	. += powered_by(/datum/cap_system/power, role = POWER_ROLE_AREA_SUPPLY)
	. += apc_steps()
	// Not an APC's: it isn't dismantled into a machine frame, and has no dark sprite (its own steps and
	// draw() cover both).
	. = without(., /datum/capability/deconstruct)
	. = without(., /datum/capability/powered)

/// The APC's own entries: the frame and electronics steps, the touch, the alt-click lock and the bash
/// (everything its bundles don't cover), plus its versions of the hatch's lock (drawn as its own glow),
/// emag (the old wait and refusals; the bluescreen layer, drawn under everything) and cover rules (the
/// cover can't close on an unsecured board). A same-key capability replaces the bundle's in place.
/obj/machinery/power/apc/proc/apc_steps()
	return list(
		cap_lock(access = list(ACCESS_ENGINE_EQUIP), blocked_by = COVER | PANEL, layer = CAP_NO_LAYER),
		cap_layer_order(cap_emag(say = "You emag the APC interface.", effect = PROC_REF(on_emag), delay = 0.6 SECONDS, blocked_by = COVER | PANEL, needs = PROC_REF(emag_ok), log = LOG_GAME, layer = "emagged"), 0),
		cap_hatch_rules(PROC_REF(cover_holds)),
		cap_entry_costs(cap_tool("Remove power control board", TOOL_CROWBAR, PROC_REF(remove_board), delay = 5 SECONDS, behind = COVER, needs = PROC_REF(board_removable), priority = 15, applies = PROC_REF(board_unsecured)), start = /datum/msg/start/apc/remove_board, volume = 50),
		cap_entry_costs(cap_entry_delay(cap_use_on("Insert power control board", /obj/item/module/power_control, PROC_REF(insert_board), behind = COVER, needs = PROC_REF(board_fits), works_broken = TRUE, works_unpowered = TRUE, priority = 20, applies = PROC_REF(no_board)), 1 SECOND), start = /datum/msg/start/apc/insert_board),
		cap_tool("Secure electronics", TOOL_SCREWDRIVER, PROC_REF(toggle_board_secure), behind = COVER, needs = PROC_REF(board_securable), name_proc = PROC_REF(board_secure_name)),
		cap_entry_costs(cap_entry_delay(cap_use_on("Add cables", /obj/item/stack/cable_coil, PROC_REF(add_cables), behind = COVER, needs = PROC_REF(cables_fit), works_broken = TRUE, works_unpowered = TRUE, priority = 20, applies = PROC_REF(terminal_missing)), 2 SECONDS), start = /datum/msg/start/apc/add_cables),
		cap_entry_costs(cap_tool("Dismantle power terminal", TOOL_WIRECUTTER, PROC_REF(cut_terminal), delay = 5 SECONDS, behind = COVER, needs = PROC_REF(floor_exposed), applies = PROC_REF(terminal_cuttable)), start = /datum/msg/start/apc/cut_terminal, volume = 0),
		cap_entry_costs(cap_tool("Cut from the wall", TOOL_WELDER, PROC_REF(cut_frame), delay = 5 SECONDS, behind = COVER, applies = PROC_REF(frame_bare)), start = /datum/msg/start/apc/cut_frame, amount = 3, volume = 25),
		cap_entry_costs(cap_entry_delay(cap_use_on("Replace damaged cover", /obj/item/frame/apc, PROC_REF(replace_cover), behind = COVER, needs = PROC_REF(cover_replaceable), works_broken = TRUE, works_unpowered = TRUE, priority = 20), 5 SECONDS), start = /datum/msg/start/apc/replace_cover),
		cap_entry_costs(cap_tool("Reset", TOOL_MULTITOOL, PROC_REF(reset_apc), delay = 5 SECONDS, behind = COVER, needs = PROC_REF(cell_out_for_reset), applies = PROC_REF(is_subverted)), start = /datum/msg/start/apc/reset),
		cap_entry_point(cap_hand("Use", PROC_REF(use_by_hand), needs = TYPE_PROC_REF(/atom, cap_in_reach), works_broken = TRUE, works_unpowered = TRUE), INTERACTION_ENTRY_HAND, gated = FALSE),
		cap_entry_point(cap_hand("Toggle lock", PROC_REF(alt_toggle_lock), needs = TYPE_PROC_REF(/atom, cap_in_reach), works_broken = TRUE, works_unpowered = TRUE), INTERACTION_ENTRY_ALT, gated = FALSE, consumes_input = FALSE),
		cap_entry_point(cap_use_on("Hit", /obj/item, PROC_REF(use_item), needs = TYPE_PROC_REF(/atom, cap_in_reach), works_broken = TRUE, works_unpowered = TRUE, priority = -10), INTERACTION_ENTRY_ITEM, gated = FALSE),
	)

MSG_DEF(start/apc/remove_board, "You begin to remove the power control board...", null)
MSG_DEF(start/apc/insert_board, "You start to insert the power control board into the frame...", "%U% inserts the power control board into %T%.")
MSG_DEF(start/apc/add_cables, "You start adding cables to the APC frame...", "%U% adds cables to the APC frame.")
MSG_DEF(start/apc/cut_terminal, "You begin to cut the cables...", "%U% starts dismantling %T%'s power terminal.")
MSG_DEF(start/apc/cut_frame, "You start welding the APC frame...", "%U% begins cutting apart %T% with %I%.")
MSG_DEF(start/apc/replace_cover, "You begin to replace the damaged APC cover...", "%U% begins replacing the damaged APC cover with a new one.")
MSG_DEF(start/apc/reset, "You begin resetting the APC...", "%U% connects %I% to the APC and begins resetting it.")

/// maintenance_hatch(cover_locked_while =): why the cover can't move now, or null.
/obj/machinery/power/apc/proc/cover_holds(mob/user, obj/item/held)
	if(cover_is_open(src))
		return has_electronics == APC_HAS_ELECTRONICS_WIRED ? "take the power control board out first" : null
	if(is_broken(src))
		return "it's broken"
	if(coverlocked && !has_stat(MAINT) && cell_charge_percent(src) > CELL_BAY_LOW_PERCENT)
		return "the cover is locked and cannot be opened"
	return null

// ---- slot hooks (cell_bay) ----

/obj/machinery/power/apc/slot_refusal(slot, obj/item/item, mob/user)
	if(slot == nameof(cell))
		if(has_stat(MAINT))
			return "You need to install the wiring and electronics first."
		if(item.w_class != ITEMSIZE_NORMAL)
			return "\The [item] is too [item.w_class < ITEMSIZE_NORMAL ? "small" : "large"] to work here."
	return ..()

/obj/machinery/power/apc/slot_inserted(slot, obj/item/item, mob/user)
	if(slot == nameof(cell))
		sync_cell_charge()
		chargecount = 0
		power_sync()

/obj/machinery/power/apc/slot_ejected(slot, obj/item/item, mob/user)
	if(slot == nameof(cell))
		item.update_icon() // ALLOW(sys_dx_old_forms): the cell is a legacy-drawn item
		charging = 0
		power_sync()

// ---- the frame and electronics ----

/obj/machinery/power/apc/proc/board_unsecured()
	return has_electronics == APC_HAS_ELECTRONICS_WIRED

/obj/machinery/power/apc/proc/board_removable(mob/user, obj/item/held)
	return terminal ? "disconnect the wires first" : TRUE

/obj/machinery/power/apc/proc/remove_board(mob/user, obj/item/held)
	has_electronics = APC_HAS_ELECTRONICS_NONE
	if(has_stat(BROKEN))
		act_message(user, src, self = span_notice("You broke the charred power control board and remove the remains."), others = span_warning("%U% has broken the charred power control board inside %T%!"), blind = "You hear a crack!")
	else
		act_message(user, src, self = span_notice("You remove the power control board."), others = span_warning("%U% has removed the power control board from %T%!"))
		new /obj/item/module/power_control(loc)
	return TRUE

/obj/machinery/power/apc/proc/no_board()
	return has_electronics == APC_HAS_ELECTRONICS_NONE

/obj/machinery/power/apc/proc/board_fits(mob/user, obj/item/held)
	return has_stat(BROKEN) ? "it is too broken for that; repair it first" : TRUE

/obj/machinery/power/apc/proc/insert_board(mob/user, obj/item/held)
	has_electronics = APC_HAS_ELECTRONICS_WIRED
	reboot()
	to_chat(user, span_notice("You place the power control board inside the frame."))
	consume(held, user)
	return TRUE

/obj/machinery/power/apc/proc/board_secure_name(mob/user)
	return has_electronics == APC_HAS_ELECTRONICS_SECURED ? "Unfasten electronics" : "Secure electronics"

/obj/machinery/power/apc/proc/board_securable(mob/user, obj/item/held)
	if(cell)
		return "remove the power cell first"
	if(has_electronics == APC_HAS_ELECTRONICS_SECURED || (has_electronics == APC_HAS_ELECTRONICS_WIRED && terminal))
		return TRUE
	return "there is nothing to secure"

/obj/machinery/power/apc/proc/toggle_board_secure(mob/user, obj/item/held)
	if(has_electronics == APC_HAS_ELECTRONICS_SECURED)
		has_electronics = APC_HAS_ELECTRONICS_WIRED
		stat_add(MAINT)
		to_chat(user, "You unfasten the electronics.")
	else
		has_electronics = APC_HAS_ELECTRONICS_SECURED
		stat_remove(MAINT)
		to_chat(user, "You screw the circuit electronics into place.")
	wake_for_power_dependency()
	return TRUE

/obj/machinery/power/apc/proc/terminal_missing()
	return !terminal && has_electronics != APC_HAS_ELECTRONICS_SECURED

/obj/machinery/power/apc/proc/floor_exposed(mob/user, obj/item/held)
	var/turf/T = loc
	if(istype(T) && !T.is_plating())
		return "you must remove the floor plating in front of the APC first"
	return TRUE

/obj/machinery/power/apc/proc/cables_fit(mob/user, obj/item/stack/cable_coil/held)
	. = floor_exposed(user, held)
	if(. != TRUE)
		return
	if(!istype(held) || held.get_amount() < 10)
		return "you need ten lengths of cable for that"
	return TRUE

/obj/machinery/power/apc/proc/add_cables(mob/user, obj/item/stack/cable_coil/held)
	var/turf/T = loc
	if(!istype(T) || held.get_amount() < 10)
		return refuse(user, "You need ten lengths of cable for that.")
	var/obj/structure/cable/N = T.get_cable_node()
	if(prob(50) && electrocute_mob(user, N, N))
		fx_sparks(src, 5)
		if(user.has_status(EFFECT_STUNNED))
			return TRUE
	held.use(10)
	act_message(user, src, self = "You add cables to the APC frame.", others = span_warning("%U% has added cables to the APC frame!"))
	make_terminal()
	terminal.connect_to_network()
	return TRUE

/obj/machinery/power/apc/proc/terminal_cuttable()
	return terminal && has_electronics != APC_HAS_ELECTRONICS_SECURED

/obj/machinery/power/apc/proc/cut_terminal(mob/user, obj/item/held)
	if(prob(50) && electrocute_mob(user, terminal.power_region, terminal))
		fx_sparks(src, 5)
		if(user.has_status(EFFECT_STUNNED))
			return TRUE
	new /obj/item/stack/cable_coil(loc, 10)
	to_chat(user, span_notice("You cut the cables and dismantle the power terminal."))
	qdel(terminal)
	return TRUE

/obj/machinery/power/apc/proc/frame_bare()
	return has_electronics == APC_HAS_ELECTRONICS_NONE && !terminal

/obj/machinery/power/apc/proc/cut_frame(mob/user, obj/item/held)
	if(is_emagged(src) || has_stat(BROKEN) || cover_removed(src))
		new /obj/item/stack/material/steel(loc)
		act_message(user, src, self = span_notice("You disassembled the broken APC frame."), others = span_warning("%T% has been cut apart by %U% with %I%."), blind = "You hear welding.", item = held)
	else
		new /obj/item/frame/apc(loc)
		act_message(user, src, self = span_notice("You cut the APC frame from the wall."), others = span_warning("%T% has been cut from the wall by %U% with %I%."), blind = "You hear welding.", item = held)
	qdel(src)
	return TRUE

/obj/machinery/power/apc/proc/cover_replaceable(mob/user, obj/item/held)
	if(!has_stat(BROKEN))
		return "it isn't broken"
	if(cell)
		return "you need to remove the power cell first"
	return TRUE

/obj/machinery/power/apc/proc/replace_cover(mob/user, obj/item/held)
	act_message(user, src, self = "You replace the damaged APC cover with a new one.", others = span_notice("%U% has replaced the damaged APC cover with a new one."))
	consume(held, user)
	atom_fix()
	reboot()
	cap_set(src, CAP_COVER_REMOVED, FALSE)
	return TRUE

/obj/machinery/power/apc/proc/is_subverted()
	return hacker || is_emagged(src)

/obj/machinery/power/apc/proc/cell_out_for_reset(mob/user, obj/item/held)
	return cell ? "you need to remove the power cell first" : TRUE

/obj/machinery/power/apc/proc/reset_apc(mob/user, obj/item/held)
	act_message(user, src, self = "You finish resetting the APC.", others = span_notice("%U% resets the APC with a beep from %I%."), item = held)
	play_sfx(src, SFX_MACHINES_CHIME, 0.5)
	reboot()
	return TRUE

// ---- the emag ----

/obj/machinery/power/apc/proc/emag_ok(mob/user, obj/item/held)
	if(hacker)
		return "nothing happens"
	if(has_stat(BROKEN | MAINT))
		return "it isn't working"
	return TRUE

/obj/machinery/power/apc/proc/on_emag(mob/user, obj/item/card/emag/card)
	flick("sparks", src)
	set_locked(FALSE)
	return TRUE

// ---- the ID lock ----

/// The library swipe, with the APC's own refusals first.
/obj/machinery/power/apc/cap_lock_swipe(mob/user, obj/item/held)
	var/reason = lock_refusal()
	if(reason)
		return refuse(user, reason)
	if(wires_of(src).is_cut(WIRE_IDSCAN))
		return refuse(user, "Access denied.")
	return ..()

/obj/machinery/power/apc/proc/lock_refusal()
	if(is_emagged(src))
		return "The panel is unresponsive."
	if(cover_is_open(src))
		return "You must close the cover to swipe an ID card."
	if(panel_is_open(src))
		return "You must close the wire panel."
	if(has_stat(BROKEN | MAINT))
		return "Nothing happens."
	if(hacker)
		return "Access denied."
	return null

/// Alt-click: the lock by the user's own access (it falls through to the loot panel afterwards).
/obj/machinery/power/apc/proc/alt_toggle_lock(mob/user)
	var/reason = lock_refusal()
	if(reason)
		to_chat(user, reason)
		return TRUE
	if(allowed(user) && !wires_of(src).is_cut(WIRE_IDSCAN))
		set_locked(!is_locked(src))
		to_chat(user, "You [is_locked(src) ? "lock" : "unlock"] the APC interface.")
	else
		to_chat(user, span_warning("Access denied."))
	return TRUE

// ---- the touch and the bash ----

/obj/machinery/power/apc/proc/use_by_hand(mob/user)
	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		if(H.species.can_shred(H, FALSE, 14))
			user.setClickCooldown(user.get_attack_speed())
			act_message(user, src, self = span_notice("You slash at %T%!"), others = span_warning("%U% slashes at %T%!"))
			play_sfx(src, SFX_WEAPONS_SLASH, 2)
			add_hiddenprint(H)
			if(beenhit >= pick(3, 4) && !panel_is_open(src))
				cap_set(src, CAP_PANEL_OPEN, TRUE)
				visible_message(span_warning("The [name]'s cover flies open, exposing the wires!"))
			else if(panel_is_open(src) && wires_of(src).cut_all())
				visible_message(span_warning("The [name]'s wires are shredded!"))
			else
				beenhit += 1
			return TRUE
	// With the cover open a hand reaches in (the cell bay's eject answers first when there is a cell).
	if(cover_is_open(src) && !issilicon(user))
		return TRUE
	if(has_stat(BROKEN | MAINT))
		return TRUE
	interact(user)
	return TRUE

/obj/machinery/power/apc/proc/use_item(mob/user, obj/item/held)
	if(issilicon(user) && get_dist(src, user) > 1)
		return use_by_hand(user)
	if(cap_tell_blocked_for(user, src, held))
		return TRUE
	if(has_stat(BROKEN) && !cover_is_open(src) && held.force >= 5 && held.w_class >= ITEMSIZE_SMALL)
		act_message(user, src, self = span_danger("You hit %T% with %I%!"), others = span_danger("%T% has been hit with %I% by %U%!"), blind = "You hear a bang!", item = held)
		if(prob(20))
			cap_set(src, CAP_COVER_OPEN | CAP_COVER_REMOVED, TRUE)
			act_message(user, src, self = span_danger("You knock down the APC cover with %I%!"), others = span_danger("The APC cover was knocked down with %I% by %U%!"), blind = "You hear a bang!", item = held)
		return TRUE
	if(issilicon(user))
		return use_by_hand(user)
	if(panel_is_open(src) && !cover_is_open(src) && istype(held, /obj/item/assembly/signaler))
		return use_by_hand(user)
	to_chat(user, span_notice("The [name] looks too sturdy to bash open with \the [held.name]."))
	return TRUE

/obj/machinery/power/apc/interact(mob/user)
	if(!user)
		return
	if(panel_is_open(src) && !isAI(user))
		wires_of(src).Interact(user)
		return
	return tgui_interact(user)

// ─────────────────────────────────────────────────────────────────────────────
// Powernet integration
// ─────────────────────────────────────────────────────────────────────────────

/obj/machinery/power/apc/connect_to_network(bind_now = TRUE)
	// Override: the APC's own vg_entity is the network node (rust_architecture.md
	// step 3: ApcTick is a row law over Apc + InRegion<Cables>), placed at the
	// terminal's cell -- the terminal object itself is a construction/visual
	// anchor only, not separately bound.
	if(!terminal)
		make_terminal()
	if(terminal)
		terminal.connect_to_network(bind_now)
		if(vg_entity)
			vg_power_bind_machine(vg_entity, terminal.x, terminal.y, terminal.z)
			if(bind_now)
				power_bind_now()
	power_sync()
	return !!power_region

/obj/machinery/power/apc/drain_power(drain_check, surge, amount = 0)
	wake_for_power_dependency()
	if(drain_check)
		return 1

	// Fully draining an APC cell would break charging; reset charging state.
	charging = 0
	changed(src)

	var/drained_energy = 0

	// Draw from the grid first (like draining from a cable).
	if(terminal && terminal.power_region)
		power_warn(terminal.power_region)
		drained_energy += power_draw(terminal.power_region, amount, terminal)

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
	// The wall mount (cap_wall_mount) offsets it into the wall; a built APC faces its builder's way.
	if(building)
		set_dir(ndir)
		area = get_area(src)
		rel_set(area(), nameof(/area::apc), src)
		cap_set(src, CAP_COVER_OPEN, TRUE)
		operating = 0
		name = "[area().name] APC"
		stat_add(MAINT)
		return

	init()
	return INITIALIZE_HINT_LATELOAD

/obj/machinery/power/apc/LateInitialize()
	update()

/obj/machinery/power/apc/ownership()
	. = ..()
	. += owns(nameof(cell), policy = OWN_SPILL)

/obj/machinery/power/apc/relations()
	. = ..()
	. += rel_one(nameof(hacker), back = nameof(/mob/living/silicon/ai::hacked_apcs))
/mob/living/silicon/ai/relations()
	. = ..()
	. += rel_many(nameof(hacked_apcs), back = nameof(/obj/machinery/power/apc::hacker))

/// Phase 1 (unbind): the APC's Rust power node goes.
/obj/machinery/power/apc/lifecycle_unbind()
	. = ..()
	if(vg_entity)
		dq_power_unbind_node(src, vg_entity)

// its area loses power and its power alarm clears.
/obj/machinery/power/apc/on_destroy(force)
	if(power_alarm_raised)
		GLOB.power_alarm.clearAlarm(loc, src)
	changed(src, CHANGE_MACHINE_MODE)
	apply_area_power()
	if(area())
		rel_clear(area(), nameof(/area::apc))
		area().power_light  = 0
		area().power_equip  = 0
		area().power_environ = 0
		area().power_change()
	..()

/// Something about the APC changed (settings, cell, damage): send it to Rust.
/obj/machinery/power/apc/proc/wake_for_power_dependency()
	changed(src, CHANGE_MACHINE_MODE)
	power_sync()

/// The APC is not a network node: its terminal is.
/obj/machinery/power/apc/disconnect_from_network()
	return FALSE

/obj/machinery/power/apc/power_autoconnect()
	return

/// Sends this APC's settings and cell state to the Rust power domain
/// (generated accessors, verdigris/domains/power/src/components.rs).
/// DM's cell is authoritative for capacity (a new cell, a swap); Rust's
/// `charge` field is authoritative for charge (a law drains/fills it) --
/// power_poll() reads it back, so this never overwrites a tick's own work.
/obj/machinery/power/apc/proc/power_sync()
	if(QDELETED(src) || !vg_entity)
		return
	set_active(area()?.requires_power && !has_stat(BROKEN | MAINT) && !power_failed ? 1 : 0)
	set_has_cell(cell ? 1 : 0)
	set_failed(power_failed ? 1 : 0)
	set_shorted_or_grid_check(shorted || grid_check ? 1 : 0)
	set_operating(operating)
	set_chargemode(chargemode)
	set_chargelevel(chargelevel)
	set_capacity(cell ? cell.maxcharge : 0)
	area()?.power_loads_changed()

/// Reads back what Rust's `ApcTick` did this step (verdigris/domains/power/src/laws.rs):
/// channels, charging, the cell charge, and the load it served.
/obj/machinery/power/apc/proc/power_poll()
	if(!vg_entity)
		return
	var/charge_changed = FALSE
	if(cell)
		var/new_charge = get_charge()
		charge_changed = new_charge != cell.charge
		cell.charge = new_charge
	var/new_equipment = get_channels(0)
	var/new_lighting = get_channels(1)
	var/new_environ = get_channels(2)
	var/new_charging = get_charging()
	power_refresh_network()
	var/new_status = !power_region ? APC_EXTERNAL_POWER_NOTCONNECTED : (power_avail(power_region) > 0 && power_netexcess(power_region) < 0 ? APC_EXTERNAL_POWER_NOENERGY : (power_avail(power_region) > 0 ? APC_EXTERNAL_POWER_GOOD : APC_EXTERNAL_POWER_NOTCONNECTED))
	var/shown_changed = new_equipment != equipment || new_lighting != lighting || new_environ != environ || new_charging != charging || new_status != main_status
	equipment = new_equipment
	lighting = new_lighting
	environ = new_environ
	charging = new_charging
	main_status = new_status
	var/alarm = !!get_alarm()
	// Counts polls that saw Rust change something (tests: a settled APC hears nothing).
	if(shown_changed || charge_changed || alarm != power_alarm_raised)
		power_event_count++
	if(alarm != power_alarm_raised)
		power_alarm_raised = alarm
		if(alarm)
			GLOB.power_alarm.triggerAlarm(loc, src, hidden = alarms_hidden)
		else
			GLOB.power_alarm.clearAlarm(loc, src)
	if(shown_changed)
		changed(src)
		apply_area_power()

// APCs are pixel-shifted so they need a full refresh when dir changes.
/obj/machinery/power/apc/set_dir(new_dir)
	..()
	wall_mount_orient()
	if(terminal)
		terminal.disconnect_from_network()
		terminal.set_dir(dir)       // Terminal has same dir as master.
		terminal.connect_to_network()
	return

/// A power failure for `duration` machine service ticks (an EMP, an overload): the output stops until
/// it runs out or someone reboots it. A longer failure already running is kept.
/obj/machinery/power/apc/proc/energy_fail(duration)
	timed_set(src, nameof(power_failed), TRUE, for_time = max(round(duration), 0) * max(MACHINE_SERVICE_INTERVAL, 1), keep_longer = TRUE)

/// power_failed's setter (timed_set() writes and reverts through it): Rust and the area hear it.
/obj/machinery/power/apc/proc/set_power_failed(value)
	value = !!value
	if(power_failed == value)
		return FALSE
	power_failed = value
	changed(src)
	update()
	return TRUE
SETTER(/obj/machinery/power/apc, power_failed)

/// A newly assigned `cell`'s charge becomes Rust's `Apc.charge` (a
/// take-reconciliation adjust, §4.2: `charge` is conserved, so DM's own
/// absolute assignments to it cross as a delta, not an overwrite).
/obj/machinery/power/apc/proc/sync_cell_charge()
	if(!cell || !vg_entity)
		return
	adjust_charge(cell.charge - get_charge())

/obj/machinery/power/apc/proc/make_terminal()
	own_set(src, nameof(terminal), new /obj/machinery/power/terminal(loc))
	terminal.set_dir(dir)
	rel_set(terminal, nameof(terminal.master), src)

/obj/machinery/power/apc/proc/init()
	has_electronics = APC_HAS_ELECTRONICS_SECURED // installed and secured
	if(cell_type)
		own_set(src, nameof(cell), new cell_type(src))
		cell.charge = start_charge * cell.maxcharge / 100.0
		sync_cell_charge()

	var/area/A = loc.loc

	if(isarea(A) && !areastring)
		area = A
		name = "\improper [area().name] APC"
	else
		area = get_area_name(areastring)
		name = "\improper [area().name] APC"
	rel_set(area(), nameof(/area::apc), src)

	if(istype(area(), /area/submap))
		alarms_hidden = TRUE

	make_terminal()

// ─────────────────────────────────────────────────────────────────────────────
// Examine and look
// ─────────────────────────────────────────────────────────────────────────────

/// The frame's construction state and the panel's fault lights (the capabilities say the rest:
/// cover, wire panel, lock, broken, cell).
/obj/machinery/power/apc/examine(mob/user)
	. = ..()
	if(!Adjacent(user) || has_stat(BROKEN))
		return
	if(cover_is_open(src))
		if(!has_electronics && terminal)
			. += "The frame is wired, but the electronics are missing."
		else if(has_electronics && !terminal)
			. += "The electronics are installed, but not wired."
		else if(!has_electronics && !terminal)
			. += "It's just an empty metal frame."
	else if(!panel_is_open(src))
		if((is_locked(src) && is_emagged(src)) || hacker)
			. += "The panel is unresponsive."
		else if(is_emagged(src))
			. += "The panel is flashing an error."

/// Closed, whole, wired, and not subverted or failed: the screen and its indicators show.
/obj/machinery/power/apc/proc/apc_all_good()
	return !cover_is_open(src) && !panel_is_open(src) && !is_broken(src) && !has_stat(BROKEN | MAINT) && !is_emagged(src) && !hacker && !power_failed

/// The screen shows the fault bluescreen (subverted or failed, with the cover and panel shut).
/obj/machinery/power/apc/proc/apc_bluescreen()
	return !cover_is_open(src) && !panel_is_open(src) && (is_emagged(src) || hacker || power_failed)

// The library draws the cover, cell, wire panel, broken and emagged layers (layer_order stacks them:
// emagged, panel_open, broken, cover_open, cell) and power_channels() the channel glows.
/obj/machinery/power/apc/draw(datum/look/look)
	..()
	if(cover_removed(src))
		look.state("apc[cell ? 2 : 1]-nocover")
	else if(cover_is_open(src) && has_stat(MAINT | BROKEN))
		look.overlay("apcmaint")
	if(apc_bluescreen() && !is_emagged(src))
		look.overlay("emagged") // hacked or failed: the same bluescreen as the emag's
	if(apc_bluescreen())
		look.light(2, 0.25, "#0000FF")
	else if(apc_all_good())
		look.glow(is_locked(src) ? "locked" : "unlocked")
		look.glow("apco3-[charging]")
		var/static/list/charge_colors = list("#F86060", "#A8B0F8", "#82FF4C")
		look.light(2, 0.25, charge_colors[clamp(charging, 0, 2) + 1])

/obj/machinery/power/apc/power_channels_lit()
	return apc_all_good() && operating

// ─────────────────────────────────────────────────────────────────────────────
// power_channels() holder interface
// ─────────────────────────────────────────────────────────────────────────────

/obj/machinery/power/apc/power_channel_mode(channel)
	switch(channel)
		if(POWER_CHANNEL_EQUIPMENT)
			return equipment
		if(POWER_CHANNEL_LIGHTING)
			return lighting
		if(POWER_CHANNEL_ENVIRON)
			return environ
	return POWERCHAN_OFF

/obj/machinery/power/apc/set_power_channel_mode(channel, mode)
	var/value = setsubsystem(mode)
	switch(channel)
		if(POWER_CHANNEL_EQUIPMENT)
			equipment = value
		if(POWER_CHANNEL_LIGHTING)
			lighting = value
		if(POWER_CHANNEL_ENVIRON)
			environ = value
		else
			return FALSE
	if(vg_entity)
		set_channels(channel, value)
	changed(src)
	update()
	return TRUE

/obj/machinery/power/apc/power_channel_load(channel)
	return channel_load(channel)

/obj/machinery/power/apc/power_breaker()
	return operating

/obj/machinery/power/apc/set_power_breaker(on)
	wake_for_power_dependency()
	operating = on ? 1 : 0
	changed(src)
	update()
	return TRUE

/obj/machinery/power/apc/power_nightshift()
	return nightshift_setting

/obj/machinery/power/apc/set_power_nightshift(mode)
	nightshift_setting = mode
	update_nightshift()
	return TRUE

/obj/machinery/power/apc/power_nightshift_lit()
	return nightshift_lights

// ─────────────────────────────────────────────────────────────────────────────
// TGUI (dx_conventions.md §5): tgui_id, tgui_data() and act_<action>; power_channels() owns
// channel / breaker / nightshift and their data (data["caps"]["power"]).
// ─────────────────────────────────────────────────────────────────────────────

/obj/machinery/power/apc/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = ..()
	data["locked"] = is_locked(src)
	data["normallyLocked"] = is_locked(src)
	data["emagged"] = is_emagged(src)
	data["externalPower"] = main_status
	data["powerCellStatus"] = cell_charge_percent(src)
	data["chargeMode"] = chargemode
	data["chargingStatus"] = charging
	data["totalLoad"] = round(channel_load_total())
	data["totalCharging"] = 0
	data["failTime"] = CEILING(time_left(src, nameof(power_failed)) / (1 SECOND), 1)
	data["gridCheck"] = grid_check
	data["coverLocked"] = coverlocked
	data["siliconUser"] = user && (siliconaccess(user) || (isobserver(user) && is_admin(user)))
	data["emergencyLights"] = !emergency_lights
	return data

/obj/machinery/power/apc/proc/report()
	return "[area().name] : [equipment]/[lighting]/[environ] ([channel_load_total()]) : [cell ? cell.percent() : "N/C"] ([charging])"

/// Silicons and admin ghosts work a locked APC (and anyone the night lighting).
/obj/machinery/power/apc/proc/lock_exempt(mob/user)
	if(!user)
		return FALSE
	if(siliconaccess(user))
		return TRUE
	if(isobserver(user))
		var/mob/observer/dead/D = user
		return D.can_admin_interact()
	return FALSE

/obj/machinery/power/apc/ui_allowed(mob/user, action)
	wake_for_power_dependency()
	if(!can_use(user, TRUE))
		return FALSE
	return !is_locked(src) || lock_exempt(user) || action == "nightshift"

/obj/machinery/power/apc/ui_logged()
	return GLOB.apc_ui_logged

GLOBAL_LIST_INIT(apc_ui_logged, list("lock" = LOG_GAME, "cover" = LOG_GAME, "charge" = LOG_GAME, "reboot" = LOG_GAME, "emergency_lighting" = LOG_GAME, "overload" = LOG_GAME))

/obj/machinery/power/apc/proc/act_lock(mob/user)
	if(!lock_exempt(user))
		return refuse(user, null)
	if(is_emagged(src) || has_stat(BROKEN | MAINT))
		return refuse(user, "The APC does not respond to the command.")
	set_locked(!is_locked(src))
	return TRUE

/obj/machinery/power/apc/proc/act_cover(mob/user)
	coverlocked = !coverlocked
	return TRUE

/obj/machinery/power/apc/proc/act_charge(mob/user)
	chargemode = !chargemode
	if(!chargemode)
		charging = 0
	power_sync()
	return TRUE

/obj/machinery/power/apc/proc/act_reboot(mob/user)
	timed_cancel(src, nameof(power_failed))
	set_power_failed(FALSE)
	return TRUE

/obj/machinery/power/apc/proc/act_emergency_lighting(mob/user)
	emergency_lights = !emergency_lights
	for(var/obj/machinery/light/L in area())
		if(!initial(L.no_emergency))
			L.no_emergency = emergency_lights
			L.update(FALSE)
		CHECK_TICK
	return TRUE

/obj/machinery/power/apc/proc/act_overload(mob/user)
	if(!lock_exempt(user))
		return refuse(user, null)
	overload_lighting()
	return TRUE

// update() — send settings to Rust and push channel state to the area.
/obj/machinery/power/apc/proc/update()
	power_sync()
	apply_area_power()

/// Pushes the channel state to the area; fires area.power_change() (the
/// machinery power signals) only when a channel changed.
/obj/machinery/power/apc/proc/apply_area_power()
	if(!area())
		return
	var/new_power_light = FALSE
	var/new_power_equip = FALSE
	var/new_power_environ = FALSE
	if(operating && !shorted && !grid_check && !power_failed)
		new_power_light = (lighting >= POWERCHAN_ON)
		new_power_equip = (equipment >= POWERCHAN_ON)
		new_power_environ = (environ >= POWERCHAN_ON)
	if(area().power_light == new_power_light && area().power_equip == new_power_equip && area().power_environ == new_power_environ)
		return
	area().power_light = new_power_light
	area().power_equip = new_power_equip
	area().power_environ = new_power_environ
	area().power_change()
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
				"load" = channel_load_total(),
			),
			"detail" = "[area()] electrical service reports [powered_channels]/3 powered channels.",
		), "power-service:[REF(src)]:[contract_power_revision]", src)

/obj/machinery/power/apc/proc/can_use(mob/user, loud = 0)
	if(!user.client)
		return 0
	if(isobserver(user) && is_admin(user))
		return 1
	if(user.stat)
		return 0
	if(!operable())
		return 0
	if(!user.IsAdvancedToolUser())
		return 0
	if(user.restrained())
		to_chat(user, span_warning("Your hands must be free to use [src]."))
		return 0
	if(user.lying)
		to_chat(user, span_warning("You must stand to use [src]!"))
		return 0
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

/obj/machinery/power/apc/proc/toggle_breaker()
	set_power_breaker(!operating)

/obj/machinery/power/apc/surplus()
	if(terminal)
		return terminal.surplus()
	else
		return 0

/obj/machinery/power/apc/proc/last_surplus()
	if(terminal && terminal.power_region)
		return power_surplus(terminal.power_region)
	else
		return 0

/obj/machinery/power/apc/draw_power(amount)
	if(terminal && terminal.power_region)
		return power_draw(terminal.power_region, amount, terminal)
	return 0

/obj/machinery/power/apc/avail()
	if(terminal)
		return terminal.avail()
	else
		return 0

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

DAMAGE_REACTION(/obj/machinery/power/apc, DAMAGE_EMP, PROC_REF(apc_emp_fail))
DAMAGE_REACTION(/obj/machinery/power/apc, DAMAGE_EXPLOSION, PROC_REF(apc_blast_wake))
DAMAGE_REACTION(/obj/machinery/power/apc, DAMAGE_BLOB, PROC_REF(apc_blob_rip_wires))

/// A blob tears the wiring out instead of damaging the frame.
/obj/machinery/power/apc/proc/apc_blob_rip_wires(datum/damage_packet/packet)
	wires_of(src).cut_all()
	cap_set(src, CAP_PANEL_OPEN, TRUE)
	return DAMAGE_REACTION_BLOCK

/// A pulse knocks the output out for a while (critical APCs resist it).
/obj/machinery/power/apc/proc/apc_emp_fail(datum/damage_packet/packet)
	wake_for_power_dependency()
	if(is_critical)
		energy_fail(rand(240, 360) / packet.severity / CRITICAL_APC_EMP_PROTECTION)
	else
		energy_fail(rand(240, 360) / packet.severity)

/// A blast wakes the power pipeline before the damage lands.
/obj/machinery/power/apc/proc/apc_blast_wake(datum/damage_packet/packet)
	wake_for_power_dependency()

/obj/machinery/power/apc/explosion_contents_severity(severity)
	return severity

/obj/machinery/power/apc/atom_break(damage_flag)
	. = ..()
	if(!.)
		return
	visible_message(span_warning("[src]'s screen flickers suddenly, then explodes in a rain of sparks and small debris!"))
	operating = 0
	changed(src)
	update()

/obj/machinery/power/apc/disconnect_terminal(obj/machinery/power/terminal/term)
	if(terminal)
		rel_clear(terminal, nameof(terminal.master))
		own_take(src, nameof(terminal))
	wake_for_power_dependency()
	changed(src)

/obj/machinery/power/apc/proc/overload_lighting(chance = 100)
	if(!operating || shorted || grid_check)
		return
	if(cell && cell.charge >= 20)
		cell.use(20)
		// One light a tick, each on its own clock.
		var/delay = 0
		for(var/obj/machinery/light/L in area())
			if(prob(chance))
				om_after(L, delay, TYPE_PROC_REF(/obj/machinery/light, surge_break))
			delay++

// ─────────────────────────────────────────────────────────────────────────────
// Lock / emag state (the machinery fields map onto cap_state)
// ─────────────────────────────────────────────────────────────────────────────

/obj/machinery/power/apc/set_locked(state)
	. = cap_set(src, CAP_LOCKED, state)
	if(.)
		changed(src, CHANGE_MACHINE_SETTINGS)

/obj/machinery/power/apc/set_emagged(state)
	. = cap_set(src, CAP_EMAGGED, state)
	if(.)
		changed(src, CHANGE_MACHINE_SETTINGS)

// ─────────────────────────────────────────────────────────────────────────────
// AI malfunction
// ─────────────────────────────────────────────────────────────────────────────

/obj/machinery/power/apc/proc/ai_hack(mob/living/silicon/ai/A = null)
	if(!A || !A.is_malf() || hacker || aidisabled || A.stat == DEAD)
		return 0
	rel_set(src, nameof(hacker), A) // two-sided: lists us in A.hacked_apcs
	set_locked(1)
	changed(src)
	return 1

// ─────────────────────────────────────────────────────────────────────────────
// Reboot
// ─────────────────────────────────────────────────────────────────────────────

/obj/machinery/power/apc/proc/reboot()
	// Reset distribution state.
	lighting = POWERCHAN_ON_AUTO
	equipment = POWERCHAN_ON_AUTO
	environ = POWERCHAN_ON_AUTO
	if(vg_entity)
		set_channels(0, equipment)
		set_channels(1, lighting)
		set_channels(2, environ)
	charging = 0
	chargecount = 0
	longtermpower = 10
	main_status = APC_EXTERNAL_POWER_NOTCONNECTED

	// Breaker off; chargemode in default state; all channels on auto.
	operating   = 0
	chargemode  = 1
	timed_cancel(src, nameof(power_failed))
	set_power_failed(FALSE)
	GLOB.power_alarm.clearAlarm(loc, src)

	// Clear malf AI ownership.
	rel_clear(src, nameof(hacker)) // two-sided: leaves the AI's hacked_apcs
	set_emagged(FALSE)
	changed(src)
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
		for(var/obj/machinery/light/L in area())
			L.flicker(rand(20, 30))
	if(prob(25))
		set_emagged(1)
		set_locked(0)
	if(prob(25))
		if(cell)
			cell.corrupt()
	if(prob(10))
		for(var/obj/machinery/computer/comp in area())
			comp.ex_act(3)
	if(prob(5))
		atom_break()

/obj/machinery/power/apc/do_grid_check()
	if(is_critical)
		return
	set_grid_check(TRUE)
	om_after(src, 15 MINUTES, PROC_REF(set_grid_check), FALSE)

/// The grid checker suspends (or releases) this APC: Rust and the machine pipeline hear it.
/obj/machinery/power/apc/proc/set_grid_check(state)
	if(grid_check == state)
		return
	grid_check = state
	power_sync()
	changed(src, CHANGE_MACHINE_SETTINGS)

/obj/machinery/power/apc/proc/set_nightshift(on, automated)
	set waitfor = FALSE // ALLOW(scheduler): update_nightshift() CHECK_TICKs over the area lights
	if(automated && istype(area(), /area/shuttle))
		return
	nightshift_lights = on
	update_nightshift()

/obj/machinery/power/apc/proc/update_nightshift()
	var/new_state = nightshift_lights
	switch(nightshift_setting)
		if(NIGHTSHIFT_NEVER)  new_state = FALSE
		if(NIGHTSHIFT_ALWAYS) new_state = TRUE
	for(var/obj/machinery/light/L in area())
		L.nightshift_mode(new_state)
		CHECK_TICK

/obj/machinery/power/apc/proc/update_area()
	var/area/NA = get_area(src)
	if(NA != area())
		if(area().apc == src)
			rel_clear(area(), nameof(/area::apc))
		rel_set(NA, nameof(/area::apc), src)
		area = NA
		name = "[area().name] APC"
	update()

/obj/machinery/power/apc/get_cell()
	return cell

/// Watts channel `index` (0 equipment, 1 lighting, 2 environment) draws now, read from Rust.
/obj/machinery/power/apc/proc/channel_load(index)
	return vg_entity ? get_static_load(index) + get_oneoff(index) : 0

/// Watts all three channels draw now.
/obj/machinery/power/apc/proc/channel_load_total()
	return channel_load(0) + channel_load(1) + channel_load(2)

/// The area this APC powers (a plain area var).
/obj/machinery/power/apc/proc/area() as /area
	return area
