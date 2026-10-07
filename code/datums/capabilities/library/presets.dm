// Bundles (doc/rewrite/dx_conventions.md §2): plain procs returning capability lists that encode the
// right relations between parts. What remains here is the legacy form of the bundles that no converted
// machine uses yet (machine_basics -> legacy_machine_basics, console, atmos_device); the final
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
	if(use_power && !power_lost())
		return "turn it off first"
	if(!can_unwrench())
		return "it's too exerted due to internal pressure"
	return TRUE

/// The unfasten entry's handler: the device comes apart into its pipe item.
/obj/machinery/atmospherics/proc/unfasten(mob/user, obj/item/held)
	act_message(user, src, self = span_notice("You unfasten %T%."), others = span_notice("%U% unfastens %T%."))
	atom_deconstruct()
	return TRUE

