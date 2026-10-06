///SCI TELEPAD///
/obj/machinery/telepad
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "telepad"
	desc = "A bluespace telepad used for teleporting objects to and from a location."
	icon = 'icons/obj/telescience.dmi'
	icon_state = "pad-idle"
	anchored = TRUE
	use_power = USE_POWER_IDLE
	circuit = /obj/item/circuitboard/telesci_pad
	idle_power_usage = 200
	active_power_usage = 5000
	var/efficiency

// This board declares no req_components, so its default parts are declared
// here instead of read off the board (roadmap C6): still resolved lazily
// into latent entries in CONTAINER_SLOT_INTERNALS, not eager objects.
/obj/machinery/telepad/latent_generator()
	// `list(circuit = 1, ...)` would use the literal identifier "circuit" as
	// the key (DM's named-argument list syntax), not circuit's value -- the
	// key must be set by index instead to be the board's actual type path.
	var/list/gen = list(
		/obj/item/bluespace_crystal = 1,
		/obj/item/stock_parts/capacitor = 2,
		/obj/item/stock_parts/console_screen = 1,
		/obj/item/stack/cable_coil = 5,
	)
	gen[circuit] = 1
	return gen

// ALLOW(init/INSTANCE_STATE): takes the parts it was built with and redraws for them
/obj/machinery/telepad/Initialize(mapload)
	. = ..()
	own_take_all(src, nameof(component_parts))
	RefreshParts()

/obj/machinery/telepad/RefreshParts()
	var/E = get_part_rating(/obj/item/stock_parts/capacitor)
	efficiency = E

EXTEND_INTERACTIONS(/obj/machinery/telepad, \
	INTERACT_INSERT(/obj/item, PROC_REF(interaction_part_replacement_impl), "Replace parts"), \
)

/**
 * Old attackby: fingerprinted on any item, then tried a part replacement,
 * falling through to the base attackby (the signal, etc.) otherwise. The
 * fingerprint applies even when the item isn't a part replacer, so this
 * can't reuse the shared /datum/interaction/machine_item/part_replacement.
 */
/obj/machinery/telepad/proc/interaction_part_replacement_impl(mob/user, obj/item/W, datum/interaction/interaction)
	add_fingerprint(user)
	return default_part_replacement(user, W) ? TRUE : FALSE

CAPABILITIES(/obj/machinery/telepad)
	op("use_multitool", tool(TOOL_MULTITOOL), priority(OP_PRIORITY_DEFAULT - 1), wait(0), then(PROC_REF(multitool_used)))

/obj/machinery/telepad/proc/multitool_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	if(!panel_open)
		return OP_OK
	var/obj/item/multitool/multitool = tool
	rel_set(multitool, nameof(multitool.connectable), src)
	to_chat(user, span_warning("You save the data in the [multitool.name]'s buffer."))
	return OP_OK
