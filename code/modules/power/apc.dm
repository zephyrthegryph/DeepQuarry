// the Area Power Controller (APC), formerly Power Distribution Unit (PDU)
// one per area, needs wire connection to power network through a terminal
//
// All APC #defines live in code/__defines/apc.dm.
//
// The distributor (channels, cell charging, load shedding) runs in Rust
// (verdigris/domains/power/src/apc.rs) every power step. The APC never polls:
// push_to_rust() sends its settings (generated: it runs once per frame after any state it
// reads changed), and power_poll() applies what Rust reports (channels, charging, status,
// alarm, the cell charge).
//
// The APC is declared (doc/rewrite/final_api.html section 16.1, doc/rewrite/conversion_guide.md): ONE CAPABILITIES list says what it is: a wall machine
// with a build ladder, a maintenance hatch (cover, panel, wires, ID lock, emag), a cell bay, its membership of the power system, its terminal and
// its hacker links, its window and the buttons in it. The imperative parts below are its own: the Rust push, the power poll, the channel and
// area bookkeeping, and the conditions and effects the declarations name.

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

	// ── area/cell wiring ────────────────────────────────────────────────────
	var/tmp/area/area
	var/areastring = null
	var/obj/item/cell/cell
	/// Cap for how fast APC cells charge, as a percentage-per-tick.
	/// 0.0005 means cellcharge is capped to ~0.05% per second.
	var/chargelevel = 0.0005
	var/start_charge = 90           // initial cell charge %
	/// The starting cell: a mapper or a subtype changes it here, and only here.
	var/cell_type = /obj/item/cell/apc

	// ── physical state ──────────────────────────────────────────────────────
	// Cover, wire panel, ID lock and emag are capability state keys (COVER_OPEN, PANEL_OPEN, LOCK_LOCKED, EMAG_EMAGGED), read through cover_open(),
	// cover_removed(), panel_open(), lock_locked() and emag_emagged(). How far the frame is built (board, cable, fastener) is the build graph's:
	// built(src, STAGE_APC_BOARD) and the stages after it.
	/// The ID lock is engaged when the APC is made (a map clears it for the APCs it leaves open).
	var/lock_at_start = TRUE
	var/grid_check = FALSE
	/// The cover lock (UI "Cover Lock"): the cover can't be pried open while the cell holds charge.
	var/coverlocked = 1
	var/obj/machinery/power/terminal/terminal = null
	var/mob/living/silicon/ai/hacker = null // Malf AI that has full control of this APC.
	power_region = 0                 // set by connect_to_network() (the APC is a network node)
	var/beenhit = 0                 // hit counter, used for Alien claws
	/// Emergency lighting is switched off for the area (the UI toggle): the area's lights read it through their area.
	var/emergency_lights = FALSE
	var/is_critical = 0
	var/alarms_hidden = FALSE       // if TRUE, power alarms from this APC are hidden on consoles
	/// NIGHTSHIFT_AUTO / _NEVER / _ALWAYS (the UI setting).
	var/nightshift_setting = NIGHTSHIFT_AUTO

	/// The power alarm is raised (as Rust last reported).
	var/power_alarm_raised = FALSE
	/// Power events applied (tests check that a settled APC hears none).
	var/power_event_count = 0
	/// The reference text of the cell whose charge became Rust's Apc.charge last (push_to_rust() reconciles a newly seated cell once).
	var/tmp/pushed_cell_ref
	/// The standing load (equipment, lighting, environment watts) Rust was last sent for this APC's area, or null when it must be sent again (a new
	/// node, a rebind): power_flush_areas() compares it with the area's demand every step.
	var/tmp/list/pushed_demand

	// ── channel state ────────────────────────────────────────────────────────
	// Rust reports these after every power step; push_to_rust() sends edits.
	var/lighting  = POWERCHAN_ON_AUTO
	var/equipment = POWERCHAN_ON_AUTO
	var/environ   = POWERCHAN_ON_AUTO
	var/operating = 1
	var/charging    = 0
	var/chargemode  = 1
	var/main_status = APC_EXTERNAL_POWER_NOTCONNECTED
	/// Monotonic revision for correction-aware contract power telemetry.
	var/contract_power_revision = 0

TRACKED(/obj/machinery/power/apc, operating)
TRACKED(/obj/machinery/power/apc, chargemode)
TRACKED(/obj/machinery/power/apc, grid_check)
TRACKED(/obj/machinery/power/apc, charging)
TRACKED(/obj/machinery/power/apc, main_status)
TRACKED(/obj/machinery/power/apc, coverlocked)
TRACKED(/obj/machinery/power/apc, nightshift_setting)
TRACKED(/obj/machinery/power/apc, emergency_lights)
TRACKED(/obj/machinery/power/apc, equipment)
TRACKED(/obj/machinery/power/apc, lighting)
TRACKED(/obj/machinery/power/apc, environ)

/// The APC distributes power now: it works (STAT_OPERABLE: not broken, its electronics fastened, no pulse or power failure holding it down).
/// What Rust and the area read; the breaker, the short and the grid check are their own settings beside it.
STAT(/obj/machinery/power/apc, supplying, ALL)
/// The power wires short it: cut, until mended; pulsed, for two minutes (power_wires()).
STAT(/obj/machinery/power/apc, shorted, ANY)
/// The AI control wire locks the AI out: cut, until mended; pulsed, for a second (ai_control()).
STAT(/obj/machinery/power/apc, aidisabled, ANY)
/// An event's power failure (energy_fail(): the electrical fault, the supermatter's shutdown): a timed hold on STAT_OPERABLE beside the
/// pulse's own (emp_disable(), source SRC_EMP). The reboot button and a reboot release both.
SOURCE_DEF(power_failure)

STAGE_DEF(apc, frame)
STAGE_DEF(apc, board)
STAGE_DEF(apc, wired)
STAGE_DEF(apc, secured)

MSG_DEF_SELF(stage/apc/frame, "It's just an empty metal frame.")
MSG_DEF_SELF(stage/apc/board, "The electronics are installed, but not wired.")
MSG_DEF_SELF(stage/apc/wired, "The frame is wired and the electronics are in, but not fastened.")
MSG_DEF_SELF(stage/apc/secured, "It is finished.")

MSG_DEF_SELF(apc/cover_locked, "The cover is locked and cannot be opened.")
MSG_DEF_SELF(apc/cover_broken, "It's broken.")
MSG_DEF_SELF(apc/board_first, "Take the power control board out first.")
MSG_DEF_SELF(apc/floor_blocks, "You must remove the floor plating in front of the APC first.")
MSG_DEF_SELF(apc/cell_first, "Remove the power cell first.")
MSG_DEF_SELF(apc/needs_electronics, "You need to install the wiring and electronics first.")
MSG_DEF_SELF(apc/ai_disabled, "The AI control for this APC has been disabled!")
MSG_DEF_SELF(apc/unresponsive, "The panel is unresponsive.")
MSG_DEF_SELF(apc/flashing_error, "The panel is flashing an error.")
MSG_DEF_SELF(apc/power_failure, "Its output has failed and it is rebooting.")
MSG_DEF_SELF(apc/unfinished, "Its electronics are not fastened.")
MSG_DEF(apc/emagged, "You emag the APC interface.", "")
MSG_DEF(apc/replaced_cover, "You replace the damaged APC cover with a new one.", "%U% has replaced the damaged APC cover with a new one.")
MSG_DEF(apc/reset_done, "You finish resetting the APC.", "%U% resets the APC with a beep from %I%.")

CAPABILITIES(/obj/machinery/power/apc)
	blast_contents()
	after_init(0, then(PROC_REF(apply_power_after_init)))
	wall_machine(/obj/item/module/power_control, repair = NONE, frame = apc_frame(), powered = FALSE, area_power = FALSE)
	configure(construction_graph(start = STAGE_APC_SECURED))
	maintenance_hatch(
		cover = cover(remove = force_pry(), replace = list(component_swap(/obj/item/frame/apc), then(PROC_REF(cover_replaced))), broken = PROC_REF(stat_is_broken)),
		// The panel opens only with the cover shut, but the cover can open over an open panel: `reach` keeps the wires out of reach then.
		wires = wires(name = "APC", count = 4, by_hand = TRUE, emp = FALSE, reach = cond_not(COVER_OPEN), status_lines = PROC_REF(wire_lights)),
		lock_wire = WIRE_IDSCAN,
		emag = list(wait(0.6 SECONDS), then(PROC_REF(emag_sparks)), sets(LOCK_LOCKED, FALSE)),
		emag_say = MSG(apc/emagged),
		panel_needs_cover_closed = TRUE,
		starts_locked = nameof(lock_at_start))
	owns_one(nameof(cell), /obj/item/cell, starts = nameof(cell_type), on_destroy = ON_DESTROY_SPILL)
	space(SPACE_CELL, inside = SPACE_HATCH, from_stage = STAGE_APC_SECURED, missing = MSG(apc/needs_electronics))
	cell_bay(nameof(cell), at = SPACE_CELL, fits = size_is(ITEMSIZE_NORMAL))
	powered_by(/datum/system/power, role = POWER_ROLE_AREA_SUPPLY)
	subversion_reset(list(tool(TOOL_MULTITOOL), at(SPACE_HATCH)), done = MSG(apc/reset_done))
	membership(joins = REGISTRY_APCS)
	emp_disable(PROC_REF(emp_outage), extends = TRUE)
	contributes(STAT_OPERABLE, PROC_REF(electronics_fastened), reason = MSG(apc/unfinished), reads = list("graph:[CAP_CONSTRUCTION]"))
	contributes(STAT_SUPPLYING, STAT_OPERABLE)
	links(/obj/machinery/power/apc::terminal, /obj/machinery/power/terminal::master)
	links(/obj/machinery/power/apc::hacker, /mob/living/silicon/ai::hacked_apcs)
	links(/obj/machinery/power/apc::area, /area::apc)
	contributes_to(nameof(area), STAT_LIGHTS_NIGHTSHIFT, PROC_REF(wants_night_lights))
	contributes_to(nameof(area), STAT_LIGHTS_EMERGENCY_OFF, nameof(emergency_lights))
	// the same rule as the wires' reach above: an open cover over the open panel keeps the signaller off the wires
	op("wires_signaler", item(/obj/item/assembly/signaler), label("Reach the wires"), at(SPACE_PANEL), when(cond_not(COVER_OPEN)), wait(0),
		then(PROC_REF(signaler_at_the_wires)))
	extend(/datum/act/hit/blob, instead(cuts_all_wires(), sets(PANEL_OPEN, TRUE)))
	// the wires: the hatch's lock brings the ID scan wire (a pulse opens it for thirty seconds); these bring the rest
	power_wires(stat = STAT_SHORTED, count = 2, pulse_lasts = 2 MINUTES, shock = 50, shock_hands_only = TRUE)
	ai_control(stat = STAT_AIDISABLED, pulse_lasts = 1 SECOND)
	on_notice(/datum/notice/attacked_by, then(PROC_REF(apc_struck)))
	on_notice(/datum/notice/slashed, then(PROC_REF(apc_slashed)))
	on_change(nameof(cell), ANY, then(PROC_REF(cell_changed)))
	on_change(nameof(supplying), ANY, then(PROC_REF(supply_changed)))
	on_change(nameof(operating), ANY, then(PROC_REF(supply_changed)))
	examine_line(PROC_REF(fault_lights_text))

	/// The APC's window and the buttons in it. The ID lock and the overload are a silicon's; every button answers only while the window is usable
	/// (ui_usable()), and the nightshift setting is the one a locked panel leaves to anyone.
	section(controls, "The APC's window and the buttons in it")
	interface("APC")
	op("breaker", ui_act(), toggles(nameof(operating)), logs(LOG_GAME))
	op("chargemode", ui_act("charge"), toggles(nameof(chargemode)), then(PROC_REF(chargemode_applied)), logs(LOG_GAME))
	op("coverlock", ui_act("cover"), toggles(nameof(coverlocked)), logs(LOG_GAME))
	op("set_channel", ui_act("channel", arg("channel", int(POWER_CHANNEL_EQUIPMENT, POWER_CHANNEL_ENVIRON)), arg("mode", int(POWERCHAN_OFF, POWERCHAN_ON_AUTO))),
		then(PROC_REF(ui_set_channel)))
	op("nightshift", ui_act(arg("nightshift", int(NIGHTSHIFT_AUTO, NIGHTSHIFT_ALWAYS))), cooldown(1 SECOND),
		then(PROC_REF(ui_set_nightshift)), logs(LOG_GAME))
	op("emergency_lighting", ui_act(), toggles(nameof(emergency_lights)), logs(LOG_GAME))
	op("reboot", ui_act(), then(PROC_REF(ui_reboot)), logs(LOG_GAME))
	op("overload", ui_act(), needs(req_silicon_or_admin()),
		then(PROC_REF(ui_overload)), logs(LOG_GAME))
	op("lock", ui_act(), needs(req_silicon_or_admin(), req_not_subverted(), req_operable()),
		toggles(LOCK_LOCKED), logs(LOG_GAME))
	extend("ui_open", needs(req_operable()))
	extend(TAG_UI, needs(req_window_usable(remote = PROC_REF(remote_control_allowed), remote_because = MSG(apc/ai_disabled))))
	extend("nightshift", drop = "lock")
	// a silicon's ctrl-click throws the breaker over its link, under the same rules as the window's button
	extend("breaker", binds(remote()), gesture(GESTURE_CTRL))

	/// The cover is latched shut while the APC is broken or its cover lock holds a charged cell in.
	section(cover_rules, "The latch on the APC's cover")
	latch(SPACE_HATCH, PROC_REF(cover_latched), because = PROC_REF(cover_latch_reason))
	param(nameof(build_dir), pos = 1)
	param(nameof(building), pos = 2)

/// The angled APC's sprite sits closer to the wall.
CAPABILITIES(/obj/machinery/power/apc/angled)
	configure(wall_mount(offset = 24, offset_ns = 20))

/// The build ladder of an APC: an empty frame, the board, ten lengths of cable (the floor plating off) and a screwdriver. The ledger refunds the board
/// and the cable; the welder takes the frame down into its item, or into scrap when it is ruined. A global bundle names holder procs by type.
/proc/apc_frame()
	return construction(start(STAGE_APC_FRAME),
		stage(STAGE_APC_BOARD, item(/obj/item/module/power_control), put_in(SLOT_CONSTRUCTION),
			then(TYPE_PROC_REF(/obj/machinery/power/apc, board_seated)), protrudes(because = MSG(apc/board_first))),
		stage(STAGE_APC_WIRED, stack(/obj/item/stack/cable_coil, 10),
			needs(req(TYPE_PROC_REF(/obj/machinery/power/apc, floor_exposed), because = MSG(apc/floor_blocks))),
			then(TYPE_PROC_REF(/obj/machinery/power/apc, terminal_wired)),
			undone(TYPE_PROC_REF(/obj/machinery/power/apc, terminal_cut)), protrudes(because = MSG(apc/board_first)),
			undo = list(tool(TOOL_WIRECUTTER))),
		// No cell can be in before this stage (SPACE_CELL exists from it): only the undo needs the bay empty.
		stage(STAGE_APC_SECURED, tool(TOOL_SCREWDRIVER),
			undo = list(tool(TOOL_SCREWDRIVER), needs(req_empty(nameof(/obj/machinery/power/apc::cell), because = MSG(apc/cell_first))))),
		dismantle(tool(TOOL_WELDER), becomes(/obj/item/frame/apc),
			needs(req_not(req_built(STAGE_APC_BOARD), because = MSG(apc/board_first))),
			ruined(TYPE_PROC_REF(/obj/machinery/power/apc, frame_ruined), becomes(/obj/item/stack/material/steel))),
		at(SPACE_HATCH))


// ---- the hatch: the latch on the cover ----

/// The cover's latch holds: the APC is broken, or the cover lock keeps a charged cell in.
/obj/machinery/power/apc/proc/cover_latched(datum/act/A)
	return !isnull(cover_latch_reason(A))

/// Why the latch holds the cover shut, or null: broken, or the cover lock over a charged cell.
/obj/machinery/power/apc/proc/cover_latch_reason(datum/act/A)
	if(broken_now())
		return /datum/msg/apc/cover_broken
	if(coverlocked && built(src, STAGE_APC_SECURED) && cell_charge_percent(src) > CELL_BAY_LOW_PERCENT)
		return /datum/msg/apc/cover_locked
	return null

/// The new cover is on (the repair step of the cover has made it whole): the APC boots again.
/obj/machinery/power/apc/proc/cover_replaced(datum/act/op/A)
	reboot()
	return OP_OK

// ---- the ladder's hooks ----

/// A ruined frame (broken, emagged, its cover gone) comes apart into scrap, not a reusable frame.
/obj/machinery/power/apc/proc/frame_ruined(datum/act/A)
	return emag_emagged(src) || broken_now() || cover_removed(src)

/// needs: the floor plating in front of the frame is off.
/obj/machinery/power/apc/proc/floor_exposed(datum/act/A)
	var/turf/T = loc
	return !istype(T) || T.is_plating()

/// The power control board went in: the frame boots.
/obj/machinery/power/apc/proc/board_seated(datum/act/op/A)
	reboot()
	return OP_OK

/// The cable went in: the terminal is made and joins the network (with a chance of a shock from the live cable).
/obj/machinery/power/apc/proc/terminal_wired(datum/act/op/A)
	var/mob/user = A.actor
	var/turf/T = loc
	var/obj/structure/cable/N = istype(T) ? T.get_cable_node() : null
	if(user && prob(50) && electrocute_mob(user, N, N))
		fx_sparks(src, 5)
	make_terminal()
	terminal.connect_to_network()
	return OP_OK

/// The wirecutters took the cable back out (with a chance of a shock): the terminal goes.
/obj/machinery/power/apc/proc/terminal_cut(datum/act/op/A)
	var/mob/user = A.actor
	if(user && terminal && prob(50) && electrocute_mob(user, terminal.power_region, terminal))
		fx_sparks(src, 5)
	if(terminal)
		spent(terminal)
	return OP_OK

/// STAT_OPERABLE: the build is finished (its last stage, the electronics fastened). An unfinished frame does not run.
/obj/machinery/power/apc/proc/electronics_fastened(datum/act/A)
	return built(src, STAGE_APC_SECURED)

/// STAT_OPERABLE's reading of the machine core's bits, for the APC: only BROKEN. The APC is its area's supply, so the area going dark (NOPOWER)
/// does not stop it; its unfinished frame is the build graph's (electronics_fastened()), its outages are holds (emp_disable(), energy_fail()).

// ---- the controls ----

/// The charge switch went over: with charging off the charging flag drops at once.
/obj/machinery/power/apc/proc/chargemode_applied(datum/act/op/A)
	if(!chargemode)
		set_charging(0)
	return OP_OK

/// The channel buttons (UI args arrive typed and validated).
/obj/machinery/power/apc/proc/ui_set_channel(datum/act/op/A, channel, mode)
	set_channel_mode(channel, mode)
	return OP_OK

/// The night lighting breaker.
/obj/machinery/power/apc/proc/ui_set_nightshift(datum/act/op/A, nightshift)
	set_nightshift_setting(nightshift)
	return OP_OK

/// The reboot button: the failure ends (a pulse's outage and an event's power failure alike).
/obj/machinery/power/apc/proc/ui_reboot(datum/act/op/A)
	end_power_failure()
	return OP_OK

/obj/machinery/power/apc/proc/ui_overload(datum/act/op/A)
	overload_lighting()
	return OP_OK

/// A silicon may work the window over its link: the AI-control wire lets silicons in, or it is the AI that hacked the APC (or one of that AI's
/// cyborgs). req_window_usable() asks it (code/library/access/window_access.dm).
/obj/machinery/power/apc/proc/remote_control_allowed(datum/act/op/A)
	if(!aidisabled)
		return TRUE
	var/mob/user = A.actor
	if(hacker && user == hacker)
		return TRUE
	var/mob/living/silicon/robot/robot = user
	return hacker && istype(robot) && robot.connected_ai == hacker // ALLOW(reads): a cyborg's master AI link is legacy silicon state, tracked in the mob conversion; read when a window button is pressed

// ---- the emag and the subversion reset ----

/// The emag op's effect, after its wait: sparks (and the ID lock lets go, which the op's own sets() does).
/obj/machinery/power/apc/proc/emag_sparks(datum/act/op/A)
	flick("sparks", src)
	return OP_OK

/// Emagged, or taken over by a malfunctioning AI (req_not_subverted() and the reset op read it).
/obj/machinery/power/apc/is_subverted()
	return hacker || ..()

/// subversion_reset's work: the APC boots clean (reboot() clears the emag and the hacker).
/obj/machinery/power/apc/reset_subversion(datum/act/op/A)
	play_sfx(src, SFX_MACHINES_CHIME, 0.5)
	reboot()
	return OP_OK

// ---- what it hears ----

/// An item used on it that no op answered (the attackby action's notice): a hard swing at a broken APC may knock its cover off. A silicon's
/// module opens the window instead (the interface's remote() binding answers that click before any swing).
/obj/machinery/power/apc/proc/apc_struck(datum/act/A)
	var/datum/notice/attacked_by/N = A
	var/mob/user = N.user
	var/obj/item/held = N.item
	if(!istype(held) || !user || issilicon(user))
		return
	if(broken_now() && !cover_open(src) && held.force >= 5 && held.w_class >= ITEMSIZE_SMALL)
		act_message(user, src, self = span_danger("You hit %T% with %I%!"), others = span_danger("%T% has been hit with %I% by %U%!"), blind = "You hear a bang!", item = held)
		if(prob(20))
			key_set(src, COVER_OPEN, TRUE)
			key_set(src, COVER_REMOVED, TRUE)
			act_message(user, src, self = span_danger("You knock down the APC cover with %I%!"), others = span_danger("The APC cover was knocked down with %I% by %U%!"), blind = "You hear a bang!", item = held)

/// A signaller held to the open wire panel: the wire window, where it can be attached to a wire.
/obj/machinery/power/apc/proc/signaler_at_the_wires(datum/act/op/A)
	wires_open(src, A.actor)
	return OP_OK

// ---- the wires ----

/// The lights under the APC's wires.
/obj/machinery/power/apc/proc/wire_lights()
	return list(
		"The APC is [lock_locked(src) ? "" : "un"]locked.",
		shorted ? "The APCs power has been shorted." : "The APC is working properly!",
		"The 'AI control allowed' light is [aidisabled ? "off" : "on"].")

/// Claws at it (the slash, which only a shredder gets): a few slashes spring the cover, then the wires are shredded.
/obj/machinery/power/apc/proc/apc_slashed(datum/act/A)
	if(beenhit >= pick(3, 4) && !panel_open(src))
		key_set(src, PANEL_OPEN, TRUE)
		visible_message(span_warning("The [name]'s cover flies open, exposing the wires!"))
	else if(panel_open(src) && wires_cut_all(src))
		visible_message(span_warning("The [name]'s wires are shredded!"))
	else
		beenhit += 1

/// emp_disable()'s outage for a pulse of `severity`: eight to twelve minutes over the severity; a critical APC shrugs most of it off.
/obj/machinery/power/apc/proc/emp_outage(severity)
	var/outage = rand(8 MINUTES, 12 MINUTES) / max(severity, 1)
	return round(is_critical ? outage / CRITICAL_APC_EMP_PROTECTION : outage)

// ─────────────────────────────────────────────────────────────────────────────
// Powernet integration
// ─────────────────────────────────────────────────────────────────────────────

/obj/machinery/power/apc/connect_to_network(bind_now = TRUE)
	// Override: the APC's own vg_entity is the network node (rust_architecture.md:
	// ApcTick is a row law over Apc + InRegion<Cables>), placed at the
	// terminal's cell -- the terminal object itself is a construction/visual
	// anchor only, not separately bound.
	if(!terminal)
		make_terminal()
	if(terminal)
		terminal.connect_to_network(bind_now)
		if(vg_entity)
			vg_power_bind_machine(vg_entity, terminal.x, terminal.y, terminal.z)
			power_node_at = null // bound at the terminal, not where power_send_node() would put it
			power_topology_edited(src)
			if(bind_now)
				power_bind_now()
	push_to_rust() // the first push after the bind: the frame's refresh may not have run yet
	seat_cell_charge(TRUE)
	pushed_demand = null // the new node takes the area's standing load at the next power step
	return !!power_region

/obj/machinery/power/apc/drain_power(drain_check, surge, amount = 0)
	if(drain_check)
		return 1

	// Fully draining an APC cell would break charging; reset charging state.
	set_charging(0)

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

/// The facing and whether it is built by hand (its constructor params).
/obj/machinery/power/apc/var/build_dir
/obj/machinery/power/apc/var/building = FALSE

// ALLOW(init/INSTANCE_STATE): a hand-built APC starts as a bare frame on its builder's wall; a mapped one starts up
/obj/machinery/power/apc/Initialize(mapload)
	if(building)
		cell_type = null // a frame built by hand starts without the cell its relation would make (starts =)
	. = ..()
	// The wall mount offsets it into the wall; a built APC faces its builder's way and starts at the bare frame.
	if(building)
		set_dir(build_dir)
		rel_set(src, nameof(area), get_area(src)) // paired: the area's apc is this APC
		key_set(src, COVER_OPEN, TRUE)
		graph_place(src, STAGE_APC_FRAME)
		set_operating(0)
		name = "[area.name] APC"
		return

	init()

/// Sets its area's power from what it supplies, once the area's machines exist.
/obj/machinery/power/apc/proc/apply_power_after_init(datum/act/timer/A)
	apply_area_power()

/// Phase 1 (unbind): the APC's Rust power node goes.
/obj/machinery/power/apc/lifecycle_unbind()
	. = ..()
	if(vg_entity)
		dq_power_unbind_node(src, vg_entity)

// its area loses power and its power alarm clears.
/obj/machinery/power/apc/on_destroy(force)
	if(power_alarm_raised)
		GLOB.power_alarm.clearAlarm(loc, src)
	var/area/served = area
	if(served)
		rel_set(src, nameof(area), null) // paired: the area no longer names this APC
		served.set_channels(FALSE, FALSE, FALSE)
	if(terminal)
		terminal.expire(0) // the terminal goes with the APC it serves
	..()

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
	native_write(src, NATIVE_APC_ACTIVE, area?.requires_power && supplying ? 1 : 0)
	native_write(src, NATIVE_APC_HAS_CELL, cell ? 1 : 0)
	native_write(src, NATIVE_APC_FAILED, supplying ? 0 : 1)
	native_write(src, NATIVE_APC_SHORTED_OR_GRID_CHECK, shorted || grid_check ? 1 : 0)
	native_write(src, NATIVE_APC_OPERATING, operating)
	native_write(src, NATIVE_APC_CHARGEMODE, chargemode)
	native_write(src, NATIVE_APC_CHARGELEVEL, chargelevel)
	native_write(src, NATIVE_APC_CAPACITY, cell ? cell.maxcharge : 0)
	native_write(src, NATIVE_APC_CHANNELS, equipment, POWER_CHANNEL_EQUIPMENT)
	native_write(src, NATIVE_APC_CHANNELS, lighting, POWER_CHANNEL_LIGHTING)
	native_write(src, NATIVE_APC_CHANNELS, environ, POWER_CHANNEL_ENVIRON)

/// A cell went in or out (the cell var changed): a newly seated cell's charge becomes Rust's.
/obj/machinery/power/apc/proc/cell_changed(datum/act/A)
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

/// Sets the seated cell's charge from outside the power step (an event that drains or refills every APC): the cell and Rust's Apc.charge both
/// take it, as a conserved delta, so the next poll does not put the old charge back.
/obj/machinery/power/apc/proc/set_cell_charge(amount)
	if(!cell)
		return
	var/before = cell.charge
	cell.charge = clamp(amount, 0, cell.maxcharge)
	if(vg_entity && pushed_cell_ref == REF(cell))
		adjust_charge(cell.charge - before)

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
	set_equipment(new_equipment)
	set_lighting(new_lighting)
	set_environ(new_environ)
	set_charging(new_charging)
	set_main_status(new_status)
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
		apply_area_power()

// APCs are pixel-shifted so they need a full refresh when dir changes.
/obj/machinery/power/apc/set_dir(new_dir)
	..()
	wall_mount_orient(src)
	if(terminal)
		terminal.disconnect_from_network()
		terminal.set_dir(dir)       // Terminal has same dir as master.
		terminal.connect_to_network()
	return

/// An event's power failure for `duration` machine service ticks (the electrical fault, the supermatter's shutdown): the APC is held out of
/// operation until it runs out or someone reboots it. A longer failure already running is kept (the hold never shortens).
/obj/machinery/power/apc/proc/energy_fail(duration)
	var/lasts = max(round(duration), 0) * max(MACHINE_SERVICE_INTERVAL, 1 TICK)
	if(lasts <= 0)
		return
	log_world("APC_POWER_FAILURE: [src] ([area]) fails for [lasts / (1 SECOND)] s")
	hold(src, STAT_OPERABLE, FALSE, SRC_POWER_FAILURE, lasts, reason = /datum/msg/apc/power_failure)

/// The failure ends now (the reboot button, a reboot): a pulse's outage and an event's power failure alike.
/obj/machinery/power/apc/proc/end_power_failure()
	release(src, STAT_OPERABLE, SRC_POWER_FAILURE)
	release(src, STAT_OPERABLE, SRC_EMP)

/// Time left on the failure that holds the APC down (deciseconds; 0 when none): the longer of a pulse's outage and an event's failure.
/obj/machinery/power/apc/proc/failure_left()
	return max(emp_disabled_left(src), hold_left(src, STAT_OPERABLE, SRC_POWER_FAILURE) || 0)

/// The output is down for a failure (a pulse or an event), as opposed to broken or unfinished: what the bluescreen shows. Its holds settle
/// STAT_OPERABLE and so `supplying` in the same step, which is what marks the look.
/obj/machinery/power/apc/proc/power_failing()
	return failure_left() > 0

/// Not supplying for its own build: broken, or its electronics not fastened (the maintenance lights behind an open cover). Read through
/// `supplying`, which the build stage settles, so the look is marked when it changes.
/obj/machinery/power/apc/proc/out_of_order()
	return broken_now() || (!supplying && !power_failing())

/// STAT_SUPPLYING or the breaker changed (a failure began or ended, it broke, its build was finished or undone, the breaker went over): the area
/// follows.
/obj/machinery/power/apc/proc/supply_changed(datum/act/A)
	apply_area_power()

/obj/machinery/power/apc/proc/make_terminal()
	rel_set(src, nameof(terminal), new /obj/machinery/power/terminal(loc)) // paired: the terminal's master is this APC
	terminal.set_dir(dir)

/obj/machinery/power/apc/proc/init()
	if(cell) // made at init by its relation (starts = nameof(cell_type))
		cell.charge = start_charge * cell.maxcharge / 100.0

	var/area/A = loc.loc
	rel_set(src, nameof(area), (isarea(A) && !areastring) ? A : get_area_name(areastring)) // paired: the area's apc is this APC
	name = "\improper [area.name] APC"

	if(istype(area, /area/submap))
		alarms_hidden = TRUE

	make_terminal()

// ─────────────────────────────────────────────────────────────────────────────
// Examine and look
// ─────────────────────────────────────────────────────────────────────────────

/// The panel's fault lights, to someone beside a working APC with its cover and panel shut (the capabilities say the rest: cover, wire panel,
/// lock, broken, cell; the build graph how far the frame is built): unresponsive when hacked or locked while emagged, else an error while emagged.
/obj/machinery/power/apc/proc/fault_lights_text(datum/act/eval/A)
	var/mob/viewer = A.actor
	if(!viewer || !Adjacent(viewer) || broken_now() || cover_open(src) || panel_open(src))
		return null
	if((lock_locked(src) && emag_emagged(src)) || hacker)
		return reason_text(/datum/msg/apc/unresponsive)
	if(emag_emagged(src))
		return reason_text(/datum/msg/apc/flashing_error)
	return null

/// The APC's own supply keeps its screen up whatever its area's power does.
/obj/machinery/power/apc/cap_powered()
	return TRUE

/// Not the normal display (is_lit() reads it): subverted, failed or unsecured, or its cover or panel open (the
/// screen and its indicators are behind them).
/obj/machinery/power/apc/screen_override()
	return !supplying || is_subverted() || cover_open(src) || panel_open(src)

/// The screen shows the fault bluescreen (subverted or failed, with the cover and panel shut).
/obj/machinery/power/apc/proc/apc_bluescreen()
	return !cover_open(src) && !panel_open(src) && (emag_emagged(src) || hacker || power_failing())

// The library draws the cover, wire panel, wires, broken, the emagged screen and lock lamp of the hatch, and the cell behind an open
// cover; the APC adds the bluescreen under everything (a hack or failure, which the emag part does not know), the coverless
// frame, the channel glows, the charge lamp and its light.
/obj/machinery/power/apc/draw(datum/look/look)
	look.part("emagged", apc_bluescreen()) // hacked, failed or emagged: the bluescreen, under the rest
	..()
	look.variant("cover-removed", when = cover_removed(src))
	look.variant("cell", when = cover_removed(src) && cell)
	look.part("maintenance", cover_open(src) && !cover_removed(src) && out_of_order())
	if(is_lit(src) && operating)
		for(var/channel in POWER_CHANNEL_EQUIPMENT to POWER_CHANNEL_ENVIRON)
			var/mode = channel_mode(channel)
			look.part("channel-[channel]", "[mode]") // a text value: mode 0 is a state too
			look.glow("channel-[channel]", "[mode]")
	if(apc_bluescreen())
		look.light(2, 0.25, "#0000FF")
	else if(is_lit(src))
		look.glow("charge", "[charging]")
		var/static/list/charge_colors = list("#F86060", "#A8B0F8", "#82FF4C")
		look.light(2, 0.25, charge_colors[clamp(charging, 0, 2) + 1])

/// One channel's mode (POWERCHAN_*), as the channel var holds it.
/obj/machinery/power/apc/proc/channel_mode(channel)
	switch(channel)
		if(POWER_CHANNEL_EQUIPMENT)
			return equipment
		if(POWER_CHANNEL_LIGHTING)
			return lighting
		if(POWER_CHANNEL_ENVIRON)
			return environ
	return POWERCHAN_OFF

/// One channel's mode (POWERCHAN_*): the setting, the Rust copy and the area's power follow.
/obj/machinery/power/apc/proc/set_channel_mode(channel, mode)
	var/value = setsubsystem(mode)
	switch(channel)
		if(POWER_CHANNEL_EQUIPMENT)
			set_equipment(value)
		if(POWER_CHANNEL_LIGHTING)
			set_lighting(value)
		if(POWER_CHANNEL_ENVIRON)
			set_environ(value)
		else
			return FALSE
	apply_area_power()
	return TRUE

// ─────────────────────────────────────────────────────────────────────────────
// The window (doc/rewrite/final_api.html section 13): ui_data() is its data; its buttons are the ops of the list above
// ─────────────────────────────────────────────────────────────────────────────

/obj/machinery/power/apc/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/channels = list()
	var/static/list/channel_titles = list("Equipment", "Lighting", "Environment")
	for(var/channel in POWER_CHANNEL_EQUIPMENT to POWER_CHANNEL_ENVIRON)
		channels += list(list(
			"title" = channel_titles[channel + 1],
			"powerLoad" = round(channel_load(channel)),
			"status" = channel_mode(channel),
			"topicParams" = list(
				"auto" = list("channel" = channel, "mode" = POWERCHAN_ON_AUTO),
				"on" = list("channel" = channel, "mode" = POWERCHAN_ON),
				"off" = list("channel" = channel, "mode" = POWERCHAN_OFF_AUTO),
			),
		))
	return list(
		"locked" = lock_locked(src),
		"emagged" = emag_emagged(src),
		"externalPower" = main_status,
		"powerCellStatus" = cell_charge_percent(src),
		"chargeMode" = chargemode,
		"chargingStatus" = charging,
		"totalLoad" = round(channel_load_total()),
		"failTime" = CEILING(failure_left() / (1 SECOND), 1),
		"gridCheck" = grid_check,
		"coverLocked" = coverlocked,
		"siliconUser" = user && (siliconaccess(user) || (isobserver(user) && is_admin(user))),
		"emergencyLights" = !emergency_lights,
		"powerChannels" = channels,
		"isOperating" = operating,
		"nightshiftLights" = area?.lights_nightshift,
		"nightshiftSetting" = nightshift_setting)

/// Pushes the channel state to the area; fires area.power_change() (the machinery power signals) only when a channel changed. The push to
/// Rust is push_to_rust()'s (generated: it follows the state it reads).
/obj/machinery/power/apc/proc/apply_area_power()
	if(!area)
		return
	var/new_power_light = FALSE
	var/new_power_equip = FALSE
	var/new_power_environ = FALSE
	if(operating && !shorted && !grid_check && supplying)
		new_power_light = (lighting >= POWERCHAN_ON)
		new_power_equip = (equipment >= POWERCHAN_ON)
		new_power_environ = (environ >= POWERCHAN_ON)
	if(!area.set_channels(new_power_equip, new_power_light, new_power_environ))
		return
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
			"detail" = "[area] electrical service reports [powered_channels]/3 powered channels.",
		), "power-service:[REF(src)]:[contract_power_revision]", src)

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
// Channel state machine
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

// ─────────────────────────────────────────────────────────────────────────────
// Damage / destruction
// ─────────────────────────────────────────────────────────────────────────────

/obj/machinery/power/apc/atom_break(damage_flag)
	. = ..()
	if(!.)
		return
	visible_message(span_warning("[src]'s screen flickers suddenly, then explodes in a rain of sparks and small debris!"))
	set_operating(0)

/obj/machinery/power/apc/disconnect_terminal(obj/machinery/power/terminal/term)
	if(terminal)
		rel_clear(src, nameof(terminal)) // paired: leaves the terminal's master too

/obj/machinery/power/apc/proc/overload_lighting(chance = 100)
	if(!operating || shorted || grid_check)
		return
	if(cell && cell.charge >= 20)
		set_cell_charge(cell.charge - 20) // the cell and the power domain's charge together
		// One light a tick, each on its own clock.
		var/delay = 0
		for(var/obj/machinery/light/L as anything in area_lights())
			if(prob(chance))
				after(L, delay, TYPE_PROC_REF(/obj/machinery/light, surge_break), key = "surge_break")
			delay++

// ─────────────────────────────────────────────────────────────────────────────
// AI malfunction
// ─────────────────────────────────────────────────────────────────────────────

/obj/machinery/power/apc/proc/ai_hack(mob/living/silicon/ai/A = null)
	if(!A || !A.is_malf() || hacker || aidisabled || A.stat == DEAD)
		return 0
	rel_set(src, nameof(hacker), A) // two-sided: lists us in A.hacked_apcs
	key_set(src, LOCK_LOCKED, TRUE)
	return 1

// ─────────────────────────────────────────────────────────────────────────────
// Reboot
// ─────────────────────────────────────────────────────────────────────────────

/obj/machinery/power/apc/proc/reboot()
	// Reset distribution state.
	set_lighting(POWERCHAN_ON_AUTO)
	set_equipment(POWERCHAN_ON_AUTO)
	set_environ(POWERCHAN_ON_AUTO)
	set_charging(0)
	set_main_status(APC_EXTERNAL_POWER_NOTCONNECTED)

	// Breaker off; chargemode in default state; all channels on auto.
	set_operating(0)
	set_chargemode(1)
	end_power_failure()
	GLOB.power_alarm.clearAlarm(loc, src)
	power_alarm_raised = FALSE

	// Clear malf AI ownership.
	rel_clear(src, nameof(hacker)) // two-sided: leaves the AI's hacked_apcs
	key_set(src, EMAG_EMAGGED, FALSE)
	apply_area_power()

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
		key_set(src, EMAG_EMAGGED, TRUE)
		key_set(src, LOCK_LOCKED, FALSE)
	if(prob(25))
		if(cell)
			cell.corrupt()
	if(prob(10))
		for(var/obj/machinery/computer/comp as anything in area_consoles(area))
			comp.ex_act(3)
	if(prob(5))
		atom_break()

/obj/machinery/power/apc/do_grid_check()
	if(is_critical)
		return
	set_grid_check(TRUE)
	after(src, 15 MINUTES, PROC_REF(set_grid_check), key = "grid_check", with = list(FALSE))

/// STAT_LIGHTS_NIGHTSHIFT of its area (section 16.11): the UI setting, and on "automatic" the station's night (the night-shift system's flag,
/// read through its accessor) for an APC on a station level outside a shuttle.
/obj/machinery/power/apc/proc/wants_night_lights(datum/act/A)
	switch(nightshift_setting)
		if(NIGHTSHIFT_ALWAYS)
			return TRUE
		if(NIGHTSHIFT_AUTO)
			return night_shift_active() && on_station_outside_shuttles()
	return FALSE

/// The APC stands on a station level, outside a shuttle: the station's night reaches it. Neither can change: an APC never moves and the map's
/// station levels are fixed for the round.
/obj/machinery/power/apc/proc/on_station_outside_shuttles()
	return (z in using_map.station_levels) && !istype(area, /area/shuttle) // ALLOW(reads): an APC is fixed to its wall, so its z level never changes while it exists

/// The blueprints redrew the areas: the APC serves the area it now stands in.
/obj/machinery/power/apc/proc/update_area()
	var/area/NA = get_area(src)
	if(NA != area)
		rel_set(src, nameof(area), NA) // paired: the old area lets go, the new one names this APC
		name = "[area.name] APC"
	apply_area_power()

/obj/machinery/power/apc/get_cell()
	return cell

/// Watts channel `index` (0 equipment, 1 lighting, 2 environment) draws now, read from Rust.
/obj/machinery/power/apc/proc/channel_load(index)
	return vg_entity ? get_static_load(index) + get_oneoff(index) : 0

/// Watts all three channels draw now.
/obj/machinery/power/apc/proc/channel_load_total()
	return channel_load(0) + channel_load(1) + channel_load(2)

/// The lights of the area this APC powers (a copy, the loops yield).
/obj/machinery/power/apc/proc/area_lights()
	return area ? area.lights_here() : list()

