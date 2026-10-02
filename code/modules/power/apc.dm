
// the Area Power Controller (APC), formerly Power Distribution Unit (PDU)
// one per area, needs wire connection to power network through a terminal
//
// All APC #defines live in code/__defines/apc.dm.
//
// M3: the distributor (channels, cell charging, load shedding) runs in Rust
// (verdigris/domains/power/src/apc.rs) every power step. The APC never polls:
// push_to_rust() sends its settings (generated: it runs once per frame after any state it
// reads changed), and power_poll() applies what Rust reports (channels, charging, status,
// alarm, the cell charge).
//
// Foundation (doc/rewrite/foundation.md): the APC is declared, not scripted. Its type vars name what
// it is built from (machine_board, machine_wires, req_access); capabilities() composes bundles (wall
// machine, maintenance hatch, cell bay, power channels, power-system membership), a construction
// ladder (board, cable, fastener) and a few ops; relations() its links; reactions() only what it hears
// (a hit, a slash); draw() its look. Its Rust pushes, redraws and window refreshes are generated from what
// push_to_rust(), draw() and tgui_data() read.

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

/obj/machinery/power/apc/angled/capabilities()
	. = ..()
	. = replace(., /datum/capability/wall_mount, new /datum/capability/wall_mount/apc_angled)

/// The angled APC's sprite sits closer to the wall.
/datum/capability/wall_mount/apc_angled

/datum/capability/wall_mount/apc_angled/orient(atom/holder)
	holder.pixel_x = (holder.dir & 3) ? 0 : (holder.dir == 4 ? 24 : -24)
	holder.pixel_y = (holder.dir & 3) ? (holder.dir == 1 ? 20 : -20) : 0

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
	machine_board = /obj/item/module/power_control
	machine_wires = /datum/wires/apc
	emag_msg = "You emag the APC interface."
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
	// cover_removed(), panel_is_open(), is_locked(), is_emagged(). How far the frame is built (board, cable,
	// fastener) is the construction ladder's: built_past(src, "frame" / "board" / "wired").
	var/shorted = 0
	var/grid_check = FALSE
	/// The cover lock (UI "Cover Lock"): the cover can't be pried open while the cell holds charge.
	var/coverlocked = 1
	var/aidisabled = 0
	var/obj/machinery/power/terminal/terminal = null
	var/mob/living/silicon/ai/hacker = null // Malf AI that has full control of this APC.
	power_region = 0                 // set by connect_to_network() (the APC IS a network node now, step 3)
	var/debug = 0
	var/beenhit = 0                 // hit counter, used for Alien claws
	/// Emergency lighting is switched off for the area (the UI toggle): the area's lights read it through their area.
	var/emergency_lights = FALSE
	var/is_critical = 0
	/// An EMP / power failure is on (timed_set() ends it: time_left(src, nameof(power_failed))).
	var/power_failed = FALSE
	var/alarms_hidden = FALSE       // if TRUE, power alarms from this APC are hidden on consoles
	/// The station's night shift asks for night lighting here (the night-shift service's command).
	var/nightshift_lights = FALSE
	/// NIGHTSHIFT_AUTO / _NEVER / _ALWAYS (the UI setting).
	var/nightshift_setting = NIGHTSHIFT_AUTO

	/// The power alarm is raised (as Rust last reported).
	var/power_alarm_raised = FALSE
	/// Power events applied (tests check that a settled APC hears none).
	var/power_event_count = 0
	/// The reference text of the cell whose charge became Rust's Apc.charge last (push_to_rust() reconciles a newly seated cell once).
	var/tmp/pushed_cell_ref

	// ── channel state ────────────────────────────────────────────────────────
	// Rust reports these after every power step; push_to_rust() sends edits.
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

TRACKED_BRIDGED(/obj/machinery/power/apc, shorted, CHANGE_MACHINE_SETTINGS)
TRACKED_BRIDGED(/obj/machinery/power/apc, operating, CHANGE_MACHINE_SETTINGS)
TRACKED_BRIDGED(/obj/machinery/power/apc, chargemode, CHANGE_MACHINE_SETTINGS)
TRACKED_BRIDGED(/obj/machinery/power/apc, grid_check, CHANGE_MACHINE_SETTINGS)
TRACKED(/obj/machinery/power/apc, nightshift_lights)
TRACKED(/obj/machinery/power/apc, nightshift_setting)
TRACKED(/obj/machinery/power/apc, emergency_lights)

// ─────────────────────────────────────────────────────────────────────────────
// Capabilities
// ─────────────────────────────────────────────────────────────────────────────

/obj/machinery/power/apc/capabilities()
	. = ..()
	// A wall machine that isn't dismantled into a machine frame (its ladder cuts it from the wall), has no
	// repair step (a new cover does) and no dark sprite (draw() says its own).
	. += wall_machine(dismantle = NONE, repair = NONE, powered = FALSE)
	. += maintenance_hatch(cover_holds = PROC_REF(cover_holds), panel_needs_cover_closed = TRUE)
	. += cell_bay(nameof(cell), at = BAY_HATCH, needs = PROC_REF(cell_bay_ready), size = ITEMSIZE_NORMAL)
	. += power_channels(/datum/capability/power_channels/apc)
	. += powered_by(/datum/system/power, role = POWER_ROLE_AREA_SUPPLY)
	. += cap_construction(
		ladder_options(at = BAY_HATCH, undo_delay = 5 SECONDS, dismantle = ladder_dismantle(tool = TOOL_WELDER, becomes = /obj/item/frame/apc, amount = 1, when_ruined = PROC_REF(frame_ruined), ruined_becomes = /obj/item/stack/material/steel)),
		stage("frame", desc = "It's just an empty metal frame."),
		// The power control board goes in (a new APC boots) and comes out by hand.
		build_insert(/obj/item/module/power_control, name = "board", desc = "The electronics are installed, but not wired.", on_enter = PROC_REF(board_seated)),
		// Ten cable lengths make the terminal (the floor plating must be off); wirecutters cut it out again.
		build_wire(10, name = "wired", desc = "The frame is wired and the electronics are in, but not fastened.", needs = PROC_REF(floor_exposed), undo_needs = PROC_REF(floor_exposed), on_enter = PROC_REF(terminal_wired), on_leave = PROC_REF(terminal_cut)),
		// A screwdriver secures the electronics (the APC works), with the cell out both ways.
		build_fasten(TOOL_SCREWDRIVER, name = "secured", needs = PROC_REF(cell_out), else_say = "remove the power cell first", undo_needs = PROC_REF(cell_out), undo_else_say = "remove the power cell first", on_enter = PROC_REF(electronics_secured), on_leave = PROC_REF(electronics_unsecured)),
	)
	. += apc_ops()
	// What the lock and the emag additionally need (the hatch declared their ops; refine() edits one in place).
	. += cap_require(CAP_LOCK, needs = list(req_not_subverted(), req_wire(WIRE_IDSCAN), req_working()))
	. += cap_require(CAP_EMAG, needs = list(req_not_subverted(), req_working()))
	. += refine(CAP_EMAG, delay = 0.6 SECONDS, effect = PROC_REF(on_emag))

/// The APC's own ops: the interface, a new cover, the multitool reset.
/obj/machinery/power/apc/proc/apc_ops()
	. = list()
	// An empty hand or a silicon's touch. With the cover open a hand takes the cell out first: the cell bay's hand eject
	// ("eject_cell") answers the same click at OP_PRIORITY_TAKE_OUT, and the board's hand step at the ladder's priority,
	// both above this op's; a shredder's claws are the claw op's (OP_PRIORITY_CLAW). Nothing here hides the interface.
	. += cap_control("Open interface", PROC_REF(open_interface), using = EMPTY_HAND, needs = req_working(), key = "open_interface")
	. += cap_op("Replace damaged cover", PROC_REF(replace_cover), using = /obj/item/frame/apc, at = BAY_HATCH, delay = 5 SECONDS, needs = PROC_REF(cover_replaceable), start_msg = /datum/msg/start/apc/replace_cover, kind = OP_STRUCTURAL, key = "replace_cover")
	. += cap_op("Reset", PROC_REF(reset_apc), using = TOOL_MULTITOOL, at = BAY_HATCH, delay = 5 SECONDS, needs = PROC_REF(cell_out_for_reset), offered = req_proc(TYPE_PROC_REF(/atom, is_subverted)), start_msg = /datum/msg/start/apc/reset, kind = OP_STRUCTURAL, key = "reset_apc")

MSG_DEF(start/apc/replace_cover, "You begin to replace the damaged APC cover...", "%U% begins replacing the damaged APC cover with a new one.")
MSG_DEF(start/apc/reset, "You begin resetting the APC...", "%U% connects %I% to the APC and begins resetting it.")

/obj/machinery/power/apc/relations()
	. = ..()
	// The cell the APC starts with is its cell_type (a map or subtype override picks another; null: none).
	. += rel_one(nameof(cell), /obj/item/cell, kind = RELK_OWNED, policy = OWN_SPILL, starts = nameof(cell_type))
	. += rel_one(nameof(terminal), /obj/machinery/power/terminal, kind = RELK_PAIRED, back = nameof(/obj/machinery/power/terminal::master))
	. += rel_one(nameof(hacker), /mob/living/silicon/ai, back = nameof(/mob/living/silicon/ai::hacked_apcs))

/mob/living/silicon/ai/relations()
	. = ..()
	. += rel_many(nameof(hacked_apcs), back = nameof(/obj/machinery/power/apc::hacker))

/// Only what the APC hears: a swing at it, a shredder's claws, a newly seated cell and what hits it (a pulse, a
/// blast, a blob). (Its pushes to Rust, its redraws and its window refreshes are generated from what
/// push_to_rust(), draw() and tgui_data() read.)
/obj/machinery/power/apc/reactions()
	. = ..()
	. += on_notice(/datum/notice/hit, PROC_REF(on_hit))
	. += on_notice(/datum/notice/slashed, PROC_REF(on_slashed))
	. += on_change(list(nameof(cell)), PROC_REF(cell_changed))
	. += before_op(damage(DAMAGE_EMP), PROC_REF(apc_emp_fail))
	. += before_op(damage(DAMAGE_EXPLOSION), PROC_REF(apc_blast_wake))
	. += before_op(damage(DAMAGE_BLOB), PROC_REF(apc_blob_rip_wires))


// ---- the hatch and the frame ----

/// maintenance_hatch(cover_holds =): why the cover can't move now, or null.
/obj/machinery/power/apc/proc/cover_holds(mob/user, obj/item/held)
	if(cover_is_open(src))
		return board_unfastened() ? "take the power control board out first" : null
	if(is_broken(src))
		return "it's broken"
	if(coverlocked && !has_stat(MAINT) && cell_charge_percent(src) > CELL_BAY_LOW_PERCENT)
		return "the cover is locked and cannot be opened"
	return null

/// The board is in (the ladder is past its bare frame) but not secured (its last stage): the cover can't close on it.
/// built_past() is strict (a later stage than the named one), so this holds on "board" and "wired" alike.
/obj/machinery/power/apc/proc/board_unfastened()
	return built_past(src, "frame") && ladder_of(src)?.state_of(src) != "secured"

/// A ruined frame (broken, emagged, its cover gone) comes apart into scrap, not a reusable frame.
/obj/machinery/power/apc/proc/frame_ruined()
	return is_emagged(src) || has_stat(BROKEN) || cover_removed(src)

// ---- the ladder's hooks ----

/// needs: the floor plating in front of the frame is off.
/obj/machinery/power/apc/proc/floor_exposed(mob/user, obj/item/held)
	var/turf/T = loc
	if(istype(T) && !T.is_plating())
		return "you must remove the floor plating in front of the APC first"
	return TRUE

/// needs (the cell bay): the electronics are in and secured.
/obj/machinery/power/apc/proc/cell_bay_ready(mob/user, obj/item/held)
	return has_stat(MAINT) ? "You need to install the wiring and electronics first." : TRUE

/// needs: the power cell is out.
/obj/machinery/power/apc/proc/cell_out(mob/user, obj/item/held)
	return !cell

/// The board went in: the frame boots.
/obj/machinery/power/apc/proc/board_seated(mob/user, obj/item/held, before)
	reboot()
	return TRUE

/// The cable went in: the terminal is made and joins the network (with a chance of a shock from the live cable).
/obj/machinery/power/apc/proc/terminal_wired(mob/user, obj/item/held, before)
	var/turf/T = loc
	var/obj/structure/cable/N = istype(T) ? T.get_cable_node() : null
	if(user && prob(50) && electrocute_mob(user, N, N))
		fx_sparks(src, 5)
	make_terminal()
	terminal.connect_to_network()
	return TRUE

/// The wirecutters took the cable back out (with a chance of a shock): the terminal goes.
/obj/machinery/power/apc/proc/terminal_cut(mob/user, obj/item/held, after)
	if(after != "board") // a step forward, not an undo
		return TRUE
	if(user && terminal && prob(50) && electrocute_mob(user, terminal.power_region, terminal))
		fx_sparks(src, 5)
	if(terminal)
		qdel(terminal)
	return TRUE

/// The electronics were fastened: the APC is finished.
/obj/machinery/power/apc/proc/electronics_secured(mob/user, obj/item/held, before)
	stat_remove(MAINT)
	changed(src)
	return TRUE

/// The electronics were unfastened.
/obj/machinery/power/apc/proc/electronics_unsecured(mob/user, obj/item/held, after)
	if(after == "wired")
		stat_add(MAINT)
		changed(src)
	return TRUE

// ---- ops ----

/// The touch: the interface window (the wires with the panel open).
/obj/machinery/power/apc/proc/open_interface(mob/user)
	interact(user)
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

/// Emagged, or taken over by a malfunctioning AI (req_not_subverted() and the reset op read it).
/obj/machinery/power/apc/is_subverted()
	return hacker || ..()

/obj/machinery/power/apc/proc/cell_out_for_reset(mob/user, obj/item/held)
	return cell ? "you need to remove the power cell first" : TRUE

/obj/machinery/power/apc/proc/reset_apc(mob/user, obj/item/held)
	act_message(user, src, self = "You finish resetting the APC.", others = span_notice("%U% resets the APC with a beep from %I%."), item = held)
	play_sfx(src, SFX_MACHINES_CHIME, 0.5)
	reboot()
	return TRUE

// ---- the emag ----

/// The emag op's effect (refine(CAP_EMAG, effect =)): sparks, and the ID lock lets go.
/obj/machinery/power/apc/proc/on_emag(mob/user, obj/item/card/emag/card)
	flick("sparks", src)
	set_locked(FALSE)
	return TRUE

// ---- what it hears ----

/// A swing at it that nothing declared answered. A silicon's touch or a hand on the open wire panel with a
/// signaller is the interface; a heavy hit on a broken APC may knock its cover off.
/obj/machinery/power/apc/proc/on_hit(datum/notice/hit/N)
	var/mob/user = N.attacker
	var/obj/item/held = N.item
	if(issilicon(user) || (panel_is_open(src) && !cover_is_open(src) && istype(held, /obj/item/assembly/signaler)))
		interact(user)
		return
	if(has_stat(BROKEN) && !cover_is_open(src) && held.force >= 5 && held.w_class >= ITEMSIZE_SMALL)
		act_message(user, src, self = span_danger("You hit %T% with %I%!"), others = span_danger("%T% has been hit with %I% by %U%!"), blind = "You hear a bang!", item = held)
		if(prob(20))
			cap_set(src, CAP_COVER_OPEN | CAP_COVER_REMOVED, TRUE)
			act_message(user, src, self = span_danger("You knock down the APC cover with %I%!"), others = span_danger("The APC cover was knocked down with %I% by %U%!"), blind = "You hear a bang!", item = held)

/// Claws at it (the claw op, which only a shredder gets): a few slashes spring the cover, then the wires are shredded.
/obj/machinery/power/apc/proc/on_slashed(datum/notice/slashed/N)
	if(beenhit >= pick(3, 4) && !panel_is_open(src))
		cap_set(src, CAP_PANEL_OPEN, TRUE)
		visible_message(span_warning("The [name]'s cover flies open, exposing the wires!"))
	else if(panel_is_open(src) && wires_of(src).cut_all())
		visible_message(span_warning("The [name]'s wires are shredded!"))
	else
		beenhit += 1

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
	push_to_rust() // the first push after the bind: the frame's refresh may not have run yet
	seat_cell_charge(TRUE)
	area()?.power_loads_changed() // the new node takes the area's static loads
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
	if(building)
		cell_type = null // a frame built by hand starts without the cell its relation would make (starts =)
	. = ..()
	// The wall mount (cap_wall_mount) offsets it into the wall; a built APC faces its builder's way.
	if(building)
		set_dir(ndir)
		area = get_area(src)
		rel_set(area(), nameof(/area::apc), src)
		cap_set(src, CAP_COVER_OPEN, TRUE)
		set_operating(0)
		name = "[area().name] APC"
		stat_add(MAINT)
		return

	init()
	return INITIALIZE_HINT_LATELOAD

/obj/machinery/power/apc/LateInitialize()
	update()

/// Phase 1 (unbind): the APC's Rust power node goes.
/obj/machinery/power/apc/lifecycle_unbind()
	. = ..()
	if(vg_entity)
		dq_power_unbind_node(src, vg_entity)

// its area loses power and its power alarm clears.
/obj/machinery/power/apc/on_destroy(force)
	if(power_alarm_raised)
		GLOB.power_alarm.clearAlarm(loc, src)
	changed(src)
	apply_area_power()
	if(area())
		rel_clear(area(), nameof(/area::apc))
		area().power_light  = 0
		area().power_equip  = 0
		area().power_environ = 0
		area().power_change()
	..()

/// Something about the APC changed (settings, cell, damage): the push to Rust follows (generated).
/obj/machinery/power/apc/proc/wake_for_power_dependency()
	changed(src)

/// The APC is not a network node: its terminal is.
/obj/machinery/power/apc/disconnect_from_network()
	return FALSE

/obj/machinery/power/apc/power_autoconnect()
	return

/// Sends this APC's settings and cell state to the Rust power domain (generated accessors,
/// verdigris/domains/power/src/components.rs). The framework runs it once per frame after any state it
/// reads changed (the generated rust_push reads), so no caller pushes by hand. The cell is authoritative
/// for capacity; Rust's `charge` field is authoritative for charge (a law drains/fills it), and
/// power_poll() reads it back. It writes nothing: a newly seated cell is cell_changed()'s, the area's static loads
/// are the area's (its apc relation) and connect_to_network()'s.
/obj/machinery/power/apc/push_to_rust()
	if(QDELETED(src) || !vg_entity)
		return
	native_write(src, NATIVE_APC_ACTIVE, area()?.requires_power && !has_stat(BROKEN | MAINT) && !power_failed ? 1 : 0)
	native_write(src, NATIVE_APC_HAS_CELL, cell ? 1 : 0)
	native_write(src, NATIVE_APC_FAILED, power_failed ? 1 : 0)
	native_write(src, NATIVE_APC_SHORTED_OR_GRID_CHECK, shorted || grid_check ? 1 : 0)
	native_write(src, NATIVE_APC_OPERATING, operating)
	native_write(src, NATIVE_APC_CHARGEMODE, chargemode)
	native_write(src, NATIVE_APC_CHARGELEVEL, chargelevel)
	native_write(src, NATIVE_APC_CAPACITY, cell ? cell.maxcharge : 0)

/// A cell went in or out (the cell relation changed): a newly seated cell's charge becomes Rust's.
/obj/machinery/power/apc/proc/cell_changed(list/keys)
	seat_cell_charge()

/// Makes the seated cell's charge Rust's Apc.charge, once per cell (`force`: again, as after a fresh bind), as a
/// conserved delta.
/obj/machinery/power/apc/proc/seat_cell_charge(force = FALSE)
	if(QDELETED(src) || !vg_entity)
		return
	var/seated_ref = cell ? REF(cell) : null
	if(!force && seated_ref == pushed_cell_ref)
		return
	pushed_cell_ref = seated_ref
	if(cell)
		adjust_charge(cell.charge - get_charge())

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
	wall_mount_reorient(src)
	if(terminal)
		terminal.disconnect_from_network()
		terminal.set_dir(dir)       // Terminal has same dir as master.
		terminal.connect_to_network()
	return

/// A power failure for `duration` machine service ticks (an EMP, an overload): the output stops until
/// it runs out or someone reboots it. A longer failure already running is kept.
/obj/machinery/power/apc/proc/energy_fail(duration)
	timed_set(src, nameof(power_failed), TRUE, for_time = max(round(duration), 0) * max(MACHINE_SERVICE_INTERVAL, 1 TICK), keep_longer = TRUE)

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

/obj/machinery/power/apc/proc/make_terminal()
	rel_set(src, nameof(terminal), new /obj/machinery/power/terminal(loc)) // paired: the terminal's master is this APC
	terminal.set_dir(dir)

/obj/machinery/power/apc/proc/init()
	ladder_set_stage(src, "secured") // installed and secured
	if(cell) // made at init by its relation (starts = nameof(cell_type))
		cell.charge = start_charge * cell.maxcharge / 100.0

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

/// The panel's fault lights (the capabilities say the rest: cover, wire panel, lock, broken, cell; the
/// ladder how far the frame is built).
/obj/machinery/power/apc/examine(mob/user)
	. = ..()
	if(!Adjacent(user) || has_stat(BROKEN))
		return
	if(!cover_is_open(src) && !panel_is_open(src))
		if((is_locked(src) && is_emagged(src)) || hacker)
			. += "The panel is unresponsive."
		else if(is_emagged(src))
			. += "The panel is flashing an error."

/// The APC's own supply keeps its screen up whatever its area's power does.
/obj/machinery/power/apc/cap_powered()
	return TRUE

/// Not the normal display (is_lit() reads it): subverted, failed or unsecured, or its cover or panel open (the
/// screen and its indicators are behind them).
/obj/machinery/power/apc/screen_override()
	return has_stat(BROKEN | MAINT) || is_subverted() || power_failed || cover_is_open(src) || panel_is_open(src)

/// The screen shows the fault bluescreen (subverted or failed, with the cover and panel shut).
/obj/machinery/power/apc/proc/apc_bluescreen()
	return !cover_is_open(src) && !panel_is_open(src) && (is_emagged(src) || hacker || power_failed)

// The library draws the cover, wire panel, wires, broken, the emagged screen, the lock lamp and the cell behind
// an open cover, and power_channels() the channel glows; the APC adds the bluescreen under everything (a hack or
// failure, which the emag part does not know), the coverless frame, the charge lamp and its light.
/obj/machinery/power/apc/draw(datum/look/look)
	look.part("emagged", apc_bluescreen()) // hacked, failed or emagged: the bluescreen, under the rest
	..()
	look.variant("cover-removed", when = cover_removed(src))
	look.variant("cell", when = cover_removed(src) && cell)
	look.part("maintenance", cover_is_open(src) && !cover_removed(src) && has_stat(MAINT | BROKEN))
	if(apc_bluescreen())
		look.light(2, 0.25, "#0000FF")
	else if(is_lit(src))
		look.glow("charge", "[charging]")
		var/static/list/charge_colors = list("#F86060", "#A8B0F8", "#82FF4C")
		look.light(2, 0.25, charge_colors[clamp(charging, 0, 2) + 1])

// ─────────────────────────────────────────────────────────────────────────────
// power_channels() holder interface: the APC's subtype of the capability (its procs take the APC as `holder`)
// ─────────────────────────────────────────────────────────────────────────────

/datum/capability/power_channels/apc

/datum/capability/power_channels/apc/channels_lit(obj/machinery/power/apc/holder)
	return is_lit(holder) && holder.operating

/datum/capability/power_channels/apc/channel_mode(obj/machinery/power/apc/holder, channel)
	switch(channel)
		if(POWER_CHANNEL_EQUIPMENT)
			return holder.equipment
		if(POWER_CHANNEL_LIGHTING)
			return holder.lighting
		if(POWER_CHANNEL_ENVIRON)
			return holder.environ
	return POWERCHAN_OFF

/datum/capability/power_channels/apc/set_channel_mode(obj/machinery/power/apc/holder, channel, mode)
	return holder.set_channel_mode(channel, mode)

/datum/capability/power_channels/apc/channel_load(obj/machinery/power/apc/holder, channel)
	return holder.channel_load(channel)

/datum/capability/power_channels/apc/breaker(obj/machinery/power/apc/holder)
	return holder.operating

/datum/capability/power_channels/apc/set_breaker(obj/machinery/power/apc/holder, on)
	holder.set_breaker(on)
	return TRUE

/datum/capability/power_channels/apc/nightshift(obj/machinery/power/apc/holder)
	return holder.nightshift_setting

/datum/capability/power_channels/apc/set_nightshift(obj/machinery/power/apc/holder, mode)
	holder.set_nightshift_setting(mode)
	return TRUE

/datum/capability/power_channels/apc/nightshift_lit(obj/machinery/power/apc/holder)
	return holder.nightshift_lights

/// One channel's mode (POWERCHAN_*): the setting, the Rust copy and the area's power follow.
/obj/machinery/power/apc/proc/set_channel_mode(channel, mode)
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
		native_write(src, NATIVE_APC_CHANNELS, value, channel)
	update()
	return TRUE

/// The main breaker.
/obj/machinery/power/apc/proc/set_breaker(on)
	set_operating(on ? 1 : 0)
	update()

// ─────────────────────────────────────────────────────────────────────────────
// TGUI (dx_conventions.md §5): tgui_id, tgui_data() and act_<action>; power_channels() owns
// channel / breaker / nightshift and their data (data["caps"]["power"]).
// ─────────────────────────────────────────────────────────────────────────────

/obj/machinery/power/apc/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state) // ALLOW(sys_tgui_data_override): the foundation UI form: tgui_data() with act_<action> procs; the sys UI_DATA declaration predates it
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

TYPE_TABLE(/obj/machinery/power/apc, ui_logged_actions, list("lock" = LOG_GAME, "cover" = LOG_GAME, "charge" = LOG_GAME, "reboot" = LOG_GAME, "emergency_lighting" = LOG_GAME, "overload" = LOG_GAME))

/obj/machinery/power/apc/proc/act_lock(mob/user)
	if(!lock_exempt(user))
		return refuse(user, null)
	var/why = is_subverted() ? /datum/msg/req_subverted : (has_stat(BROKEN | MAINT) ? /datum/msg/req_not_working : null)
	if(why)
		return refuse(user, req_reason_text(why))
	set_locked(!is_locked(src))
	return TRUE

/obj/machinery/power/apc/proc/act_cover(mob/user)
	coverlocked = !coverlocked
	return TRUE

/obj/machinery/power/apc/proc/act_charge(mob/user)
	set_chargemode(!chargemode)
	if(!chargemode)
		charging = 0
	return TRUE

/obj/machinery/power/apc/proc/act_reboot(mob/user)
	timed_cancel(src, nameof(power_failed))
	set_power_failed(FALSE)
	return TRUE

/// Switches the area's emergency lighting: the lights read it through their area and redraw themselves.
/obj/machinery/power/apc/proc/act_emergency_lighting(mob/user)
	set_emergency_lights(!emergency_lights)
	return TRUE

/obj/machinery/power/apc/proc/act_overload(mob/user)
	if(!lock_exempt(user))
		return refuse(user, null)
	overload_lighting()
	return TRUE

// update() — the push to Rust follows (generated); push channel state to the area now.
/obj/machinery/power/apc/proc/update()
	changed(src)
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
	set_breaker(!operating)

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
	changed(src)

// ─────────────────────────────────────────────────────────────────────────────
// Damage / destruction
// ─────────────────────────────────────────────────────────────────────────────

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
	set_operating(0)
	update()

/obj/machinery/power/apc/disconnect_terminal(obj/machinery/power/terminal/term)
	if(terminal)
		rel_clear(src, nameof(terminal)) // paired: leaves the terminal's master too
	wake_for_power_dependency()

/obj/machinery/power/apc/proc/overload_lighting(chance = 100)
	if(!operating || shorted || grid_check)
		return
	if(cell && cell.charge >= 20)
		cell.use(20)
		// One light a tick, each on its own clock.
		var/delay = 0
		for(var/obj/machinery/light/L as anything in area_lights())
			if(prob(chance))
				after(L, delay, TYPE_PROC_REF(/obj/machinery/light, surge_break), key = "surge_break")
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
		native_write(src, NATIVE_APC_CHANNELS, equipment, 0)
		native_write(src, NATIVE_APC_CHANNELS, lighting, 1)
		native_write(src, NATIVE_APC_CHANNELS, environ, 2)
	charging = 0
	chargecount = 0
	longtermpower = 10
	main_status = APC_EXTERNAL_POWER_NOTCONNECTED

	// Breaker off; chargemode in default state; all channels on auto.
	set_operating(0)
	set_chargemode(1)
	timed_cancel(src, nameof(power_failed))
	set_power_failed(FALSE)
	GLOB.power_alarm.clearAlarm(loc, src)

	// Clear malf AI ownership.
	rel_clear(src, nameof(hacker)) // two-sided: leaves the AI's hacked_apcs
	set_emagged(FALSE)
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
		for(var/obj/machinery/light/L as anything in area_lights())
			L.flicker(rand(20, 30))
	if(prob(25))
		set_emagged(1)
		set_locked(0)
	if(prob(25))
		if(cell)
			cell.corrupt()
	if(prob(10))
		for(var/obj/machinery/computer/comp as anything in area_members(area(), POWER_ROLE_COMPUTER))
			comp.ex_act(3)
	if(prob(5))
		atom_break()

/obj/machinery/power/apc/do_grid_check()
	if(is_critical)
		return
	set_grid_check(TRUE)
	after(src, 15 MINUTES, PROC_REF(set_grid_check), key = "grid_check", with = list(FALSE))

// The grid checker suspends (or releases) this APC: the setter is TRACKED, so Rust (rust_push), the window and the machine
// pipeline (CHANGE_MACHINE_SETTINGS) hear it.

/// The night shift asks for night lighting (the service's command): only the tracked state changes; the area's
/// lights read lights_nightshift through their area and redraw themselves.
/obj/machinery/power/apc/proc/set_nightshift(on, automated)
	if(automated && istype(area(), /area/shuttle))
		return
	set_nightshift_lights(!!on)

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

/// The lights of the area this APC powers: its MEMBER relations of role POWER_ROLE_LIGHTING (a copy, the loops yield).
/obj/machinery/power/apc/proc/area_lights()
	return area_members(area(), POWER_ROLE_LIGHTING)

/// The area this APC powers (a plain area var).
/obj/machinery/power/apc/proc/area() as /area
	return area
