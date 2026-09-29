// Bundles (doc/rewrite/dx_conventions.md §2): plain procs returning capability lists that encode the
// right relations between parts ("the ID lock only works with the cover and panel closed"). Bundles are
// plain nouns; the components they combine are cap_<noun>. A bundle is only a list: without() /
// replace() edit what it contributed, and a later capability with the same key replaces an earlier one
// in place (maintenance_hatch()'s gated panel replaces machine_basics()'s plain one).
//
//	/obj/machinery/power/apc/capabilities()
//		. = wall_machine(board = /obj/item/module/power_control)
//		. += maintenance_hatch(/datum/wires/apc, access = ACCESS_ENGINE_EQUIP, cover_locked_while = PROC_REF(cover_holds), panel_needs_cover_closed = TRUE)
//		. += cell_bay(nameof(cell))

/**
 * What every buildable machine has: a wrench to anchor it, breakage with welder repair, a maintenance
 * panel with deconstruction to its board behind it, and the dark/unpowered state. Their examine lines
 * come with them.
 */
/proc/machine_basics(board, anchored_by = TOOL_WRENCH, repair_tool = TOOL_WELDER)
	. = list(
		cap_panel(),
		cap_breakable(repair_tool = repair_tool),
		cap_power(),
	)
	if(anchored_by)
		. += cap_anchor(tool = anchored_by)
	if(board)
		. += cap_deconstruct(board, behind = PANEL)

/**
 * A wall-mounted machine: machine_basics() without anchoring (it hangs on the wall), plus the wall mount,
 * which faces it away from its wall and offsets it onto the wall.
 */
/proc/wall_machine(board, offset = 26, repair_tool = TOOL_WELDER)
	. = machine_basics(board = board, anchored_by = NONE, repair_tool = repair_tool) // NONE: DM substitutes the default for an explicit null
	. += cap_wall_mount(offset = offset)

/**
 * A maintenance hatch: a cover, the maintenance panel, the wiring behind the panel, an access lock and the
 * emag, with the rules between them built in:
 * - the cover can't be opened while `cover_locked_while` (a proc on the holder, () -> TRUE while locked)
 *   says so, and closing it is always allowed;
 * - with panel_needs_cover_closed, the panel only opens with the cover closed (the APC's wire panel);
 * - the ID lock and the emag only work with the cover and the panel closed ("close the cover first").
 * `access`: the type default (a list or one access); a mapped req_access / req_one_access overrides it.
 */
/proc/maintenance_hatch(wires, access, cover_locked_while, panel_needs_cover_closed = FALSE, cover_tool = TOOL_CROWBAR, removable_cover = FALSE, emag_say, emag_effect, emag_mode = EMAG_ONCE)
	var/datum/capability/maintenance_hatch/hatch = new
	hatch.cover_locked_while = cover_locked_while
	. = list(hatch)
	. += cap_cover(open_tool = cover_tool, removable = removable_cover, needs = cover_locked_while ? TYPE_PROC_REF(/atom, hatch_cover_free) : null)
	. += cap_panel(blocked_by = panel_needs_cover_closed ? COVER : NONE)
	if(wires)
		. += cap_wires(wires, behind = PANEL)
	if(access)
		. += cap_lock(access = islist(access) ? access : list(access), blocked_by = COVER | PANEL)
	. += cap_emag(say = emag_say, effect = emag_effect, mode = emag_mode, blocked_by = COVER | PANEL)

/// The hatch's own settings (no entries): what locks the cover.
/datum/capability/maintenance_hatch
	/// A proc on the holder, () -> TRUE while the cover must stay shut (the APC's coverlock).
	var/cover_locked_while

/// The cover's needs proc under a maintenance hatch: opening is refused while the hatch says the cover
/// is locked; closing is always allowed.
/atom/proc/hatch_cover_free(mob/user, obj/item/held)
	if(cover_is_open(src))
		return TRUE
	var/datum/capability/maintenance_hatch/hatch = cap_of_all(src, /datum/capability/maintenance_hatch)
	if(hatch?.cover_locked_while && call(src, hatch.cover_locked_while)())
		return "the cover is locked"
	return TRUE

/**
 * A computer console: breakage (the screen cracks; no welder repair), power, and taking it apart into a
 * computer frame with its board. Consoles don't unanchor.
 */
/proc/console(board)
	. = list(
		cap_breakable(repair_tool = NONE),
		cap_power(),
	)
	if(board)
		. += cap_deconstruct(board, behind = NONE)

/**
 * An atmospherics device: the wrench unfastens it into its pipe item, refused while it runs or while its
 * internal pressure is too high to release safely; and the dark/unpowered state when it uses power.
 */
/proc/atmos_device(uses_power = TRUE, unwrench_delay = 4 SECONDS)
	. = list(cap_atmos_unwrench(delay = unwrench_delay))
	if(uses_power)
		. += cap_power()

/datum/capability/atmos_unwrench
	var/delay = 4 SECONDS

/proc/cap_atmos_unwrench(delay = 4 SECONDS, log = LOG_GAME)
	var/datum/capability/atmos_unwrench/C = new
	C.delay = delay
	cap_gating(C, log = log)
	return C

/datum/capability/atmos_unwrench/interactions(atom/holder)
	return list(adopt_entry(cap_tool("Unfasten", TOOL_WRENCH, TYPE_PROC_REF(/obj/machinery/atmospherics, unfasten), delay = delay, needs = TYPE_PROC_REF(/obj/machinery/atmospherics, unwrench_refusal), works_unpowered = TRUE), id = "atmos_unwrench"))

/// Why the device can't be unfastened now (running, or too much internal pressure), else TRUE.
/obj/machinery/atmospherics/proc/unwrench_refusal(mob/user, obj/item/held)
	if(use_power && !(stat & NOPOWER))
		return "turn it off first"
	if(!can_unwrench())
		return "it's too exerted due to internal pressure"
	return TRUE

/// The unfasten entry's handler: the device comes apart into its pipe item.
/obj/machinery/atmospherics/proc/unfasten(mob/user, obj/item/held)
	act_message(user, src, self = span_notice("You unfasten %T%."), others = span_notice("%U% unfastens %T%."))
	atom_deconstruct()
	return TRUE

// ---- the wall mount ----

/**
 * cap_wall_mount(offset =): a wall-mounted holder faces away from its wall and sits `offset` pixels onto
 * it. A mapped dir is kept (maps place wall machines facing the room); a holder built at runtime with no
 * dir set looks for the wall around it.
 */
/datum/capability/wall_mount
	var/offset = 26

/proc/cap_wall_mount(offset = 26)
	var/datum/capability/wall_mount/C = new
	C.offset = offset
	return C

/datum/capability/wall_mount/on_holder_init(atom/holder, mapload)
	if(!mapload)
		var/turf/here = get_turf(holder)
		for(var/direction in GLOB.cardinal)
			var/turf/T = get_step(here, direction)
			if(iswall(T))
				holder.set_dir(REVERSE_DIR(direction))
				break
	// A holder the map placed by hand (pixel_x / pixel_y set) stays where it was put.
	if(!holder.pixel_x && !holder.pixel_y)
		holder.wall_mount_orient(offset)

/// Sits the holder `offset` pixels onto the wall behind it. Types with an odd sprite (the angled APC)
/// override it.
/atom/proc/wall_mount_orient(offset = 26)
	wall_mount_offset(src, offset)

/// Offsets holder onto the wall behind it (toward its dir).
/proc/wall_mount_offset(atom/holder, offset)
	holder.pixel_x = (holder.dir & (NORTH|SOUTH)) ? 0 : (holder.dir == EAST ? offset : -offset)
	holder.pixel_y = (holder.dir & (NORTH|SOUTH)) ? (holder.dir == NORTH ? offset : -offset) : 0
