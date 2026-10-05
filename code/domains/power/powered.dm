// The power domain's adapters (doc/rewrite/final_api.html, section 11: "powered() and powered_by() are adapters: they name the power system, so
// they are defined in the power domain, not in the library"; section 22).
//
//   powered(channel)                    the machine draws on an area power channel: it goes dark while the channel is off (a look layer and an
//                                       examine line) and STAT_OPERABLE is false without it. The channel is the machine's own power_channel var
//                                       (an airlock's ENVIRON); the param names it for the explain tools.
//   powered_by(system, role)            membership in another system: the holder joins `system` while it exists, under `role`, so the system finds
//                                       its members by role (the power system lists every area supply) without scanning atoms.

MSG_DEF_SELF(power/unpowered, "It is unpowered.")

/// The machine has power for its controls (the NOPOWER bit power_change() keeps, until phase 4 turns it into the area channel read).
/obj/machinery/proc/power_available(datum/act/A)
	return cap_powered()

/obj/machinery/proc/power_unavailable(datum/act/A)
	return !cap_powered()

CAPABILITY_TYPE(powered, CAP_POWERED, /datum/capability/lib/powered, key = NONE, channel = POWER_CHANNEL_EQUIPMENT)

/datum/capability/lib/powered

/datum/capability/lib/powered/entries()
	return list(
		contributes(STAT_OPERABLE, TYPE_PROC_REF(/obj/machinery, power_available), reason = MSG(power/unpowered), reads = list("stat")),
		look_layer(LOOK_DARK, when = TYPE_PROC_REF(/obj/machinery, power_unavailable), reads = list("stat")),
		examine_line(MSG(power/unpowered), when = TYPE_PROC_REF(/obj/machinery, power_unavailable), reads = list("stat")))

CAPABILITY_TYPE(powered_by, CAP_POWERED_BY, /datum/capability/lib/powered_by, key = of_system, of_system = null, role = null)

/datum/capability/lib/powered_by
	holder_hooks = HOLDER_HOOK_INIT | HOLDER_HOOK_DESTROY

/datum/capability/lib/powered_by/on_holder_init(datum/act/eval/A)
	var/datum/system/S = system(of_system)
	S?.kernel_join(A.holder, src, role)

/datum/capability/lib/powered_by/on_holder_destroy(datum/act/eval/A)
	var/datum/system/S = system(of_system)
	S?.kernel_leave(A.holder, src)
