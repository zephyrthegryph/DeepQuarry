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
TRACKED(/obj/machinery/power/apc, coverlocked)
TRACKED(/obj/machinery/power/apc, aidisabled)
TRACKED(/obj/machinery/power/apc, nightshift_lights)
TRACKED(/obj/machinery/power/apc, nightshift_setting)
TRACKED(/obj/machinery/power/apc, emergency_lights)
TRACKED(/obj/machinery/power/apc, equipment)
TRACKED(/obj/machinery/power/apc, lighting)
TRACKED(/obj/machinery/power/apc, environ)

/// An EMP or an overload is on: the output stops until the failure runs out or someone reboots it (a timed hold on this stat, source SRC_POWER_FAILURE).
STAT(/obj/machinery/power/apc, power_failed, ANY)
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
MSG_DEF_SELF(apc/cell_too_big, "That power cell is too large to work here.")
MSG_DEF_SELF(apc/cell_too_small, "That power cell is too small to work here.")
MSG_DEF_SELF(apc/not_broken, "It isn't broken.")
MSG_DEF_SELF(apc/cant_use, "You can't use that right now.")
MSG_DEF_SELF(apc/ai_disabled, "The AI control for this APC has been disabled!")
MSG_DEF_SELF(apc/silicons_only, "Only a silicon can do that.")
MSG_DEF_SELF(apc/unresponsive, "The panel is unresponsive.")
MSG_DEF_SELF(apc/flashing_error, "The panel is flashing an error.")
MSG_DEF(apc/emagged, "You emag the APC interface.", "")
MSG_DEF(apc/replaced_cover, "You replace the damaged APC cover with a new one.", "%U% has replaced the damaged APC cover with a new one.")
MSG_DEF(apc/reset_done, "You finish resetting the APC.", "%U% resets the APC with a beep from %I%.")

CAPABILITIES(/obj/machinery/power/apc, \
	wall_machine(/obj/item/module/power_control, repair = NONE, frame = apc_frame(), powered = FALSE), \
	configure(CAP_CONSTRUCTION, start = STAGE_APC_SECURED), \
	maintenance_hatch( \
		cover = cover(remove = force_pry(), replace = list(component_swap(/obj/item/frame/apc), at(BAY_HATCH))), \
		wires = /datum/wires/apc, \
		emag = list(wait(0.6 SECONDS), then(PROC_REF(emag_sparks)), sets(LOCK_LOCKED, FALSE)), \
		emag_say = MSG(apc/emagged), \
		panel_needs_cover_closed = TRUE, \
		starts_locked = nameof(lock_at_start)), \
	owns_one(nameof(cell), /obj/item/cell, starts = nameof(cell_type), on_destroy = ON_DESTROY_SPILL), \
	cell_bay(nameof(cell), at = BAY_HATCH), \
	powered_by(/datum/system/power, role = POWER_ROLE_AREA_SUPPLY), \
	subversion_reset(list(tool(TOOL_MULTITOOL), at(BAY_HATCH)), done = MSG(apc/reset_done)), \
	link(/obj/machinery/power/apc::terminal, /obj/machinery/power/terminal::master), \
	link(/obj/machinery/power/apc::hacker, /mob/living/silicon/ai::hacked_apcs), \
	interface("APC"), \
	op("breaker", ui_act(), toggles(nameof(operating)), then(PROC_REF(settings_applied)), logs(LOG_GAME)), \
	op("chargemode", ui_act("charge"), toggles(nameof(chargemode)), then(PROC_REF(chargemode_applied)), logs(LOG_GAME)), \
	op("coverlock", ui_act("cover"), toggles(nameof(coverlocked)), logs(LOG_GAME)), \
	op("set_channel", ui_act("channel", arg("channel", int(POWER_CHANNEL_EQUIPMENT, POWER_CHANNEL_ENVIRON)), arg("mode", int(POWERCHAN_OFF, POWERCHAN_ON_AUTO))), then(PROC_REF(ui_set_channel))), \
	op("nightshift", ui_act(arg("nightshift", int(NIGHTSHIFT_AUTO, NIGHTSHIFT_ALWAYS))), cooldown(1 SECOND), then(PROC_REF(ui_set_nightshift)), logs(LOG_GAME)), \
	op("emergency_lighting", ui_act(), toggles(nameof(emergency_lights)), logs(LOG_GAME)), \
	op("reboot", ui_act(), then(PROC_REF(ui_reboot)), logs(LOG_GAME)), \
	op("overload", ui_act(), needs(req(PROC_REF(actor_works_locked), because = MSG(apc/silicons_only))), then(PROC_REF(ui_overload)), logs(LOG_GAME)), \
	op("lock", ui_act(), needs(req(PROC_REF(actor_works_locked), because = MSG(apc/silicons_only)), req_not_subverted(), req_is(STAT_OPERABLE, because = MSG(machine/inoperable))), toggles(LOCK_LOCKED), logs(LOG_GAME)), \
	op("open_wires", hand(), when(PANEL_OPEN), priority(above("ui_open")), then(PROC_REF(open_wire_window))), \
	extend("ui_open", needs(req_is(STAT_OPERABLE, because = MSG(machine/inoperable)))), \
	extend(TAG_UI, needs(req(PROC_REF(ui_usable), because = PROC_REF(ui_unusable_reason)))), \
	extend("nightshift", drop = "lock"), \
	extend("construction.undo:apc_board", when(COVER_OPEN)), \
	extend("construction.undo:apc_wired", when(COVER_OPEN)), \
	extend("construction.undo:apc_wired", priority(above("wires.cut"))), \
	extend("construction.undo:apc_secured", when(COVER_OPEN)), \
	extend("construction.build:apc_secured", priority(above("panel.open"))), \
	extend("construction.dismantle", needs(req_not(req_built(STAGE_APC_BOARD, because = MSG(apc/board_first)), because = MSG(apc/board_first)))), \
	extend("construction.undo:apc_secured", priority(above("panel.open"))), \
	extend("construction.undo:apc_board", priority(above("open_wires"))), \
	extend("construction.undo:apc_wired", priority(above("open_wires"))), \
	extend("subversion_reset.use", priority(above("wires.pulse"))), \
	extend("cover.open", needs(req(PROC_REF(cover_free), because = PROC_REF(cover_hold_reason)))), \
	extend("cover.remove", needs(req(PROC_REF(cover_free), because = PROC_REF(cover_hold_reason)))), \
	extend("cover.replace", needs(req(PROC_REF(cover_replaceable), because = PROC_REF(cover_replace_reason)))), \
	extend("cover.replace", then(PROC_REF(cover_replaced))), \
	extend("cell_bay.cell.take", when(COVER_OPEN)), \
	extend("cell_bay.cell.insert", needs(req_built(STAGE_APC_SECURED, because = MSG(apc/needs_electronics)), req(PROC_REF(cell_fits), because = PROC_REF(cell_fit_reason)))), \
	extend("construction.undo:apc_secured", needs(req_empty(nameof(/obj/machinery/power/apc::cell), because = MSG(apc/cell_first)))), \
	extend(CAP_LOCK, needs(req_not_subverted(), req_wire(WIRE_IDSCAN), req_is(STAT_OPERABLE, because = MSG(machine/inoperable)))), \
	extend("emag.use", needs(req_not_subverted(), req_is(STAT_OPERABLE, because = MSG(machine/inoperable)))), \
	extend(/datum/act/hit/blob, instead(cuts_all_wires(), sets(PANEL_OPEN, TRUE))), \
	on_notice(/datum/notice/hit/emp, then(PROC_REF(apc_emp_fail))), \
	on_notice(/datum/notice/hit/explosion, then(PROC_REF(apc_blast_wake))), \
	on_notice(/datum/notice/legacy_hit, then(PROC_REF(apc_hit))), \
	on_notice(/datum/notice/slashed, then(PROC_REF(apc_slashed))), \
	on_change(nameof(cell), ANY, then(PROC_REF(cell_changed))), \
	on_change(nameof(power_failed), ANY, then(PROC_REF(power_failed_changed))))

/// The angled APC's sprite sits closer to the wall.
CAPABILITIES(/obj/machinery/power/apc/angled, \
	configure(CAP_WALL_MOUNT, offset = 24, offset_ns = 20))

/// The build ladder of an APC: an empty frame, the board, ten lengths of cable (the floor plating off) and a screwdriver. The ledger refunds the board
/// and the cable; the welder takes the frame down into its item, or into scrap when it is ruined. A global bundle names holder procs by type.
/proc/apc_frame()
	return construction(start(STAGE_APC_FRAME), \
		stage(STAGE_APC_BOARD, item(/obj/item/module/power_control), put_in(SLOT_CONSTRUCTION), \
			then(TYPE_PROC_REF(/obj/machinery/power/apc, board_seated))), \
		stage(STAGE_APC_WIRED, stack(/obj/item/stack/cable_coil, 10), \
			needs(req(TYPE_PROC_REF(/obj/machinery/power/apc, floor_exposed), because = MSG(apc/floor_blocks))), \
			then(TYPE_PROC_REF(/obj/machinery/power/apc, terminal_wired)), \
			undone(TYPE_PROC_REF(/obj/machinery/power/apc, terminal_cut)), \
			undo = list(tool(TOOL_WIRECUTTER))), \
		stage(STAGE_APC_SECURED, tool(TOOL_SCREWDRIVER), \
			needs(req_empty(nameof(/obj/machinery/power/apc::cell), because = MSG(apc/cell_first))), \
			then(TYPE_PROC_REF(/obj/machinery/power/apc, electronics_secured)), \
			undone(TYPE_PROC_REF(/obj/machinery/power/apc, electronics_unsecured))), \
		dismantle(tool(TOOL_WELDER), becomes(/obj/item/frame/apc), \
			ruined(TYPE_PROC_REF(/obj/machinery/power/apc, frame_ruined), becomes(/obj/item/stack/material/steel))), \
		at(BAY_HATCH))

/// The slot the board goes into: the build graph's own (SLOT_CONSTRUCTION).
/datum/om/relation/slot/apc_construction
	holder = /obj/machinery/power/apc
	slot_id = SLOT_CONSTRUCTION
	name = "construction"
	is_default = TRUE
	capacity_model = SLOT_CAPACITY_COUNT
	capacity = 1
	drop_policy = SLOT_DROP_SPILL

// ---- the hatch: what the cover and the cell bay ask of the APC ----

/// Why the cover can't move now, or null: with the cover open the board must be fastened; shut, it can't be pried open while the APC is broken or
/// its cover lock holds a charged cell in.
/obj/machinery/power/apc/proc/cover_hold_reason(datum/act/A)
	if(cover_open(src))
		return board_unfastened() ? /datum/msg/apc/board_first : null
	if(has_stat(BROKEN))
		return /datum/msg/apc/cover_broken
	if(coverlocked && !has_stat(MAINT) && cell_charge_percent(src) > CELL_BAY_LOW_PERCENT)
		return /datum/msg/apc/cover_locked
	return null

/obj/machinery/power/apc/proc/cover_free(datum/act/A)
	return isnull(cover_hold_reason(A))

/// The board is in (the build is past its bare frame) but not secured (its last stage): the cover can't close on it.
/obj/machinery/power/apc/proc/board_unfastened()
	return built(src, STAGE_APC_BOARD) && !built(src, STAGE_APC_SECURED)

/// A new cover goes on a broken APC with no cell in it.
/obj/machinery/power/apc/proc/cover_replaceable(datum/act/A)
	return has_stat(BROKEN) && !cell

/obj/machinery/power/apc/proc/cover_replace_reason(datum/act/A)
	return has_stat(BROKEN) ? /datum/msg/apc/cell_first : /datum/msg/apc/not_broken

/// The new cover is on (the component swap has repaired it): the APC boots again.
/obj/machinery/power/apc/proc/cover_replaced(datum/act/op/A)
	reboot()
	return OP_OK

/// A power cell fits when it is the size this bay takes.
/obj/machinery/power/apc/proc/cell_fits(datum/act/op/A)
	var/obj/item/held = A.held
	return !istype(held) || held.w_class == ITEMSIZE_NORMAL // ALLOW(reads): an item's size is fixed for its life, so no change can be missed

/obj/machinery/power/apc/proc/cell_fit_reason(datum/act/op/A)
	var/obj/item/held = A.held
	return (istype(held) && held.w_class < ITEMSIZE_NORMAL) ? /datum/msg/apc/cell_too_small : /datum/msg/apc/cell_too_big

// ---- the ladder's hooks ----

/// A ruined frame (broken, emagged, its cover gone) comes apart into scrap, not a reusable frame.
/obj/machinery/power/apc/proc/frame_ruined(datum/act/A)
	return emag_emagged(src) || has_stat(BROKEN) || cover_removed(src)

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
		qdel(terminal)
	return OP_OK

/// The electronics were fastened: the APC is finished.
/obj/machinery/power/apc/proc/electronics_secured(datum/act/op/A)
	stat_remove(MAINT)
	changed(src)
	return OP_OK

/// The electronics were unfastened.
/obj/machinery/power/apc/proc/electronics_unsecured(datum/act/op/A)
	stat_add(MAINT)
	changed(src)
	return OP_OK

// ---- the controls ----

/// The empty hand on an APC whose wire panel is open: the wires window.
/obj/machinery/power/apc/proc/open_wire_window(datum/act/op/A)
	if(isAI(A.actor))
		return OP_REFUSED
	wire_set_of(src)?.Interact(A.actor)
	return OP_OK

/// The breaker went over: the area follows.
/obj/machinery/power/apc/proc/settings_applied(datum/act/op/A)
	update()
	return OP_OK

/// The charge switch went over: with charging off the charging flag drops at once.
/obj/machinery/power/apc/proc/chargemode_applied(datum/act/op/A)
	if(!chargemode)
		charging = 0
	return OP_OK

/// The channel buttons (UI args arrive typed and validated).
/obj/machinery/power/apc/proc/ui_set_channel(datum/act/op/A, channel, mode)
	set_channel_mode(channel, mode)
	return OP_OK

/// The night lighting breaker.
/obj/machinery/power/apc/proc/ui_set_nightshift(datum/act/op/A, nightshift)
	set_nightshift_setting(nightshift)
	return OP_OK

/// The reboot button: the failure ends.
/obj/machinery/power/apc/proc/ui_reboot(datum/act/op/A)
	release(src, STAT_POWER_FAILED, SRC_POWER_FAILURE)
	return OP_OK

/obj/machinery/power/apc/proc/ui_overload(datum/act/op/A)
	overload_lighting()
	return OP_OK

/// Silicons and admin ghosts work a locked APC (and its overload button): the lock library's own exemption.
/obj/machinery/power/apc/proc/actor_works_locked(datum/act/op/A)
	var/mob/user = A.actor
	if(!user)
		return FALSE
	if(siliconaccess(user))
		return TRUE
	var/mob/observer/dead/ghost = user
	return istype(ghost) && ghost.can_admin_interact()

/// Why this person can't use the window or its buttons now, or null: asleep, not able to use it, an AI that lost control, out of reach.
/obj/machinery/power/apc/proc/ui_unusable_reason(datum/act/op/A)
	var/mob/user = A.actor
	if(!user)
		return /datum/msg/apc/cant_use
	var/mob/observer/dead/ghost = user
	if(istype(ghost) && ghost.can_admin_interact())
		return null
	if(user.stat)
		return /datum/msg/apc/cant_use
	if(!user.IsAdvancedToolUser() || user.restrained() || user.lying) // ALLOW(reads): a mob lying down is legacy mob state, tracked in the mob conversion; the check runs when a window button is pressed, never from a cached menu
		return /datum/msg/apc/cant_use
	if(issilicon(user))
		var/permit = FALSE
		var/mob/living/silicon/ai/AI = user
		var/mob/living/silicon/robot/robot = user
		if(hacker)
			if(hacker == AI)
				permit = TRUE
			else if(istype(robot) && robot.connected_ai && robot.connected_ai == hacker) // ALLOW(reads): a cyborg's master AI link is legacy silicon state, tracked in the mob conversion; read when a window button is pressed
				permit = TRUE
		if(aidisabled && !permit)
			return /datum/msg/apc/ai_disabled
	else if(get_dist(src, user) > 1)
		return /datum/msg/apc/cant_use
	return null

/obj/machinery/power/apc/proc/ui_usable(datum/act/op/A)
	return isnull(ui_unusable_reason(A))

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

/// A swing at it that nothing declared answered. A silicon's touch or a hand on the open wire panel with a
/// signaller is the interface; a heavy hit on a broken APC may knock its cover off.
/obj/machinery/power/apc/proc/apc_hit(datum/act/A)
	var/datum/notice/legacy_hit/N = A
	var/mob/user = N.attacker
	var/obj/item/held = N.item
	if(issilicon(user) || (panel_open(src) && !cover_open(src) && istype(held, /obj/item/assembly/signaler)))
		interact(user)
		return
	if(has_stat(BROKEN) && !cover_open(src) && held.force >= 5 && held.w_class >= ITEMSIZE_SMALL)
		act_message(user, src, self = span_danger("You hit %T% with %I%!"), others = span_danger("%T% has been hit with %I% by %U%!"), blind = "You hear a bang!", item = held)
		if(prob(20))
			cap_key_set(src, COVER_OPEN, TRUE, null)
			cap_key_set(src, COVER_REMOVED, TRUE, null)
			act_message(user, src, self = span_danger("You knock down the APC cover with %I%!"), others = span_danger("The APC cover was knocked down with %I% by %U%!"), blind = "You hear a bang!", item = held)

/// Claws at it (the slash, which only a shredder gets): a few slashes spring the cover, then the wires are shredded.
/obj/machinery/power/apc/proc/apc_slashed(datum/act/A)
	if(beenhit >= pick(3, 4) && !panel_open(src))
		cap_key_set(src, PANEL_OPEN, TRUE, null)
		visible_message(span_warning("The [name]'s cover flies open, exposing the wires!"))
	else if(panel_open(src) && wire_set_of(src).cut_all())
		visible_message(span_warning("The [name]'s wires are shredded!"))
	else
		beenhit += 1

/// A pulse knocks the output out for a while (critical APCs resist it).
/obj/machinery/power/apc/proc/apc_emp_fail(datum/act/A)
	var/datum/notice/hit/emp/N = A
	var/severity = max(N.packet?.severity, 1)
	wake_for_power_dependency()
	if(is_critical)
		energy_fail(rand(240, 360) / severity / CRITICAL_APC_EMP_PROTECTION)
	else
		energy_fail(rand(240, 360) / severity)

/// A blast wakes the power pipeline.
/obj/machinery/power/apc/proc/apc_blast_wake(datum/act/A)
	wake_for_power_dependency()

/obj/machinery/power/apc/interact(mob/user)
	if(!user)
		return
	if(panel_open(src) && !isAI(user))
		wire_set_of(src).Interact(user)
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
			power_node_at = null // bound at the terminal, not where power_send_node() would put it
			power_topology_edited(src)
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
	// The wall mount offsets it into the wall; a built APC faces its builder's way and starts at the bare frame.
	if(building)
		set_dir(ndir)
		area = get_area(src)
		rel_set(area(), nameof(/area::apc), src)
		cap_key_set(src, COVER_OPEN, TRUE, null)
		graph_place(src, STAGE_APC_FRAME)
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
	if(terminal)
		terminal.expire(0) // the terminal goes with the APC it serves
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
	wall_mount_orient(src)
	if(terminal)
		terminal.disconnect_from_network()
		terminal.set_dir(dir)       // Terminal has same dir as master.
		terminal.connect_to_network()
	return

/// A power failure for `duration` machine service ticks (an EMP, an overload): the output stops until it runs out or someone reboots it. A longer failure
/// already running is kept.
/obj/machinery/power/apc/proc/energy_fail(duration)
	var/lasts = max(round(duration), 0) * max(MACHINE_SERVICE_INTERVAL, 1 TICK)
	if(lasts <= 0)
		return
	if(lasts > hold_left(src, STAT_POWER_FAILED, SRC_POWER_FAILURE))
		hold(src, STAT_POWER_FAILED, TRUE, SRC_POWER_FAILURE, lasts)

/// power_failed changed (a hold began, ended or was released): Rust and the area hear it.
/obj/machinery/power/apc/proc/power_failed_changed(datum/act/A)
	update()

/obj/machinery/power/apc/proc/make_terminal()
	rel_set(src, nameof(terminal), new /obj/machinery/power/terminal(loc)) // paired: the terminal's master is this APC
	terminal.set_dir(dir)

/obj/machinery/power/apc/proc/init()
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
/// build graph how far the frame is built).
/obj/machinery/power/apc/examine(mob/user)
	. = ..()
	if(!Adjacent(user) || has_stat(BROKEN))
		return
	if(!cover_open(src) && !panel_open(src))
		if((lock_locked(src) && emag_emagged(src)) || hacker)
			. += reason_text(/datum/msg/apc/unresponsive)
		else if(emag_emagged(src))
			. += reason_text(/datum/msg/apc/flashing_error)

/// The APC's own supply keeps its screen up whatever its area's power does.
/obj/machinery/power/apc/cap_powered()
	return TRUE

/// Not the normal display (is_lit() reads it): subverted, failed or unsecured, or its cover or panel open (the
/// screen and its indicators are behind them).
/obj/machinery/power/apc/screen_override()
	return has_stat(BROKEN | MAINT) || is_subverted() || power_failed || cover_open(src) || panel_open(src)

/// The screen shows the fault bluescreen (subverted or failed, with the cover and panel shut).
/obj/machinery/power/apc/proc/apc_bluescreen()
	return !cover_open(src) && !panel_open(src) && (emag_emagged(src) || hacker || power_failed)

// The library draws the cover, wire panel, wires, broken, the emagged screen and lock lamp of the hatch, and the cell behind an open
// cover; the APC adds the bluescreen under everything (a hack or failure, which the emag part does not know), the coverless
// frame, the channel glows, the charge lamp and its light.
/obj/machinery/power/apc/draw(datum/look/look)
	look.part("emagged", apc_bluescreen()) // hacked, failed or emagged: the bluescreen, under the rest
	..()
	look.variant("cover-removed", when = cover_removed(src))
	look.variant("cell", when = cover_removed(src) && cell)
	look.part("maintenance", cover_open(src) && !cover_removed(src) && has_stat(MAINT | BROKEN))
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
	if(vg_entity)
		native_write(src, NATIVE_APC_CHANNELS, value, channel)
	update()
	return TRUE

/// The main breaker.
/obj/machinery/power/apc/proc/set_breaker(on)
	set_operating(on ? 1 : 0)
	update()

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
		"normallyLocked" = lock_locked(src),
		"emagged" = emag_emagged(src),
		"externalPower" = main_status,
		"powerCellStatus" = cell_charge_percent(src),
		"chargeMode" = chargemode,
		"chargingStatus" = charging,
		"totalLoad" = round(channel_load_total()),
		"totalCharging" = 0,
		"failTime" = CEILING(hold_left(src, STAT_POWER_FAILED, SRC_POWER_FAILURE) / (1 SECOND), 1),
		"gridCheck" = grid_check,
		"coverLocked" = coverlocked,
		"siliconUser" = user && (siliconaccess(user) || (isobserver(user) && is_admin(user))),
		"emergencyLights" = !emergency_lights,
		"powerChannels" = channels,
		"isOperating" = operating,
		"nightshiftLights" = nightshift_lights,
		"nightshiftSetting" = nightshift_setting)

/obj/machinery/power/apc/proc/report()
	return "[area().name] : [equipment]/[lighting]/[environ] ([channel_load_total()]) : [cell ? cell.percent() : "N/C"] ([charging])"

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

/// Channel settings changed outside the UI (wires, hacking): send them.
/obj/machinery/power/apc/proc/update_channels()
	changed(src)

// ─────────────────────────────────────────────────────────────────────────────
// Damage / destruction
// ─────────────────────────────────────────────────────────────────────────────

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
// Lock / emag state (the machinery fields map onto the capability keys)
// ─────────────────────────────────────────────────────────────────────────────

/obj/machinery/power/apc/set_locked(state)
	. = cap_key_set(src, LOCK_LOCKED, !!state, null)
	if(.)
		changed(src, CHANGE_MACHINE_SETTINGS)

/obj/machinery/power/apc/set_emagged(state)
	. = cap_key_set(src, EMAG_EMAGGED, !!state, null)
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
	set_lighting(POWERCHAN_ON_AUTO)
	set_equipment(POWERCHAN_ON_AUTO)
	set_environ(POWERCHAN_ON_AUTO)
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
	release(src, STAT_POWER_FAILED, SRC_POWER_FAILURE)
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
