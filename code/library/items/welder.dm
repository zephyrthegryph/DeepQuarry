// The lit welding tool (doc/rewrite/final_api.html, section 9 "Tool profiles and bundles"): a bundle and a requirement, for every op that welds.
//
//   op("weld", lit_welder(), wait(...), then(...))               a lit welder in hand; the profile's one unit of fuel is spent at the commit
//   op("weld", lit_welder(fuel = 0), ...)                        a lit welder that spends nothing (the weld is the work, not the fuel)
//   needs(req_welder_lit())                                      the requirement alone, beside another binding
//
// The fuel is the RES_FUEL resource (code/engine/parts/resource.dm): reserved after the last wait, spent only when the op commits, so a refused
// or interrupted weld costs nothing. What a welder needs to be lit is the tool's own (isOn()); an item that carries one (a cyborg's module, a
// welding pack's torch) answers get_welder().

MSG_DEF_SELF(welder/off, "Turn on the welding tool first!")

/// A lit welding tool in hand, spending `fuel` units of it at the commit (the welder profile's wait, sound and verbs come with tool()).
/proc/lit_welder(fuel = 1)
	return list(tool(TOOL_WELDER), costs(RES_FUEL, fuel), needs(req_welder_lit()))

/// The welding tool in hand is lit.
/proc/req_welder_lit(because = null)
	return part_make(/datum/entry/part/req/welder_lit, list("because" = because))

/datum/entry/part/req/welder_lit
	part_name = "req_welder_lit"
	default_reason = /datum/msg/welder/off

/datum/entry/part/req/welder_lit/holds(datum/act/op/A)
	var/obj/item/held = A.held
	if(!istype(held))
		return FALSE
	var/obj/item/weldingtool/welder = held.get_welder()
	return !!welder?.isOn()
