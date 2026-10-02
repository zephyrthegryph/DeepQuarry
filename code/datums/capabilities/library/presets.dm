// Bundles (doc/rewrite/dx_conventions.md §2): plain procs returning capability lists that encode the
// right relations between parts. What remains here is the legacy form of the bundles that no converted
// machine uses yet (machine_basics -> legacy_machine_basics, console, atmos_device, service_panel); the final
// forms (machine_basics, wall_machine, maintenance_hatch) are capabilities of code/library/machine/machine.dm.

/**
 * What every buildable machine has: a wrench to anchor it, breakage with welder repair (and claws that tear at it), a maintenance
 * panel with deconstruction to its board behind it, and the dark/unpowered state. Their examine lines
 * come with them. `repair`: the repair tool (NONE: no repair entry). `dismantle`: NONE leaves out the machine-frame
 * deconstruction even when a `board` is given. `powered`: FALSE leaves out the dark/unpowered state (a machine whose
 * draw() says its own).
 */
/proc/legacy_machine_basics(board, anchored_by = TOOL_WRENCH, repair = TOOL_WELDER, dismantle = TRUE, powered = TRUE)
	. = list(
		cap_panel(),
		cap_breakable(repair_tool = repair),
		claw_op(),
	)
	if(powered)
		. += cap_power()
	if(anchored_by)
		. += cap_anchor(tool = anchored_by)
	if(board && dismantle)
		. += cap_deconstruct(board, needs = req_set(PANEL))

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
		. += cap_deconstruct(board)

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
	return list(adopt_entry(lib_op("Unfasten", TYPE_PROC_REF(/obj/machinery/atmospherics, unfasten), OP_SHAPE_TOOL, using = TOOL_WRENCH, key = "unfasten", kind = OP_STRUCTURAL, delay = delay, needs = TYPE_PROC_REF(/obj/machinery/atmospherics, unwrench_refusal), works_unpowered = TRUE), id = "atmos_unwrench"))

/// Why the device can't be unfastened now (running, or too much internal pressure), else TRUE.
/obj/machinery/atmospherics/proc/unwrench_refusal(mob/user, obj/item/held)
	if(use_power && !has_stat(NOPOWER))
		return "turn it off first"
	if(!can_unwrench())
		return "it's too exerted due to internal pressure"
	return TRUE

/// The unfasten entry's handler: the device comes apart into its pipe item.
/obj/machinery/atmospherics/proc/unfasten(mob/user, obj/item/held)
	act_message(user, src, self = span_notice("You unfasten %T%."), others = span_notice("%U% unfastens %T%."))
	atom_deconstruct()
	return TRUE

/**
 * service_panel(): a maintenance panel and the wires behind it as one bundle, with no cover (archive/framework_fixes.md
 * §9.5): a vendor, a fabricator, a door controller. `wires`: the /datum/wires subtype. `panel_tool`: what opens the panel. `access`: when given (or `access_from_holder`), opening the panel
 * needs a credential for it (cap_access(): the holder's own req_access wins), unless the holder is emagged. `emag_say`:
 * when given, an emag (cap_emag(), `emag_mode`, `emag_effect`) subverts it. Each part keeps its own capability type, so
 * a subtype still replaces one (`replace(., /datum/capability/wires, cap_wires(...))`) or refines it by key.
 *
 *	. += service_panel(/datum/wires/vending, emag_say = "You short out %T%'s product lock.", emag_mode = EMAG_REPEATABLE)
 */
/proc/service_panel(wires, panel_tool = TOOL_SCREWDRIVER, list/access, access_from_holder = FALSE, emag_say, emag_effect, emag_mode = EMAG_ONCE, panel_needs)
	. = list(cap_panel(tool = panel_tool, needs = panel_needs), cap_wires(wires))
	if(length(access) || access_from_holder)
		. += cap_require("open_maintenance_panel", needs = any_of(req_set(CAP_EMAGGED), req_credential(access)))
	if(emag_say || emag_effect)
		. += cap_emag(say = emag_say, effect = emag_effect, mode = emag_mode)
