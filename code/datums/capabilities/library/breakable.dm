// The breakable capability (doc/rewrite/dx_conventions.md §2). State: CAP_BROKEN, set when the
// holder breaks (atom_break() of the obj_integrity system) and cleared when it is fixed
// (atom_fix()) or repaired with repair_tool. Every other entry refuses while broken unless it is
// works_broken (cap_gate_reason()). Layer: LOOK_BROKEN. Accessor: is_broken().
//
//	. += cap_breakable(repair_tool = TOOL_WELDER, repair_delay = 3 SECONDS)

/datum/capability/breakable
	layer_name = LOOK_BROKEN
	var/repair_tool
	var/repair_delay

/// Breaks with the holder; `repair_tool` over `repair_delay` repairs it. repair_tool = NONE: no repair
/// entry (null can't be passed: DM would substitute the default).
/proc/cap_breakable(repair_tool = TOOL_WELDER, repair_delay = 3 SECONDS, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log)
	var/datum/capability/breakable/C = new
	C.repair_tool = repair_tool
	C.repair_delay = repair_delay
	return cap_gating(C, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)

/datum/capability/breakable/interactions(atom/holder)
	if(!repair_tool)
		return null
	return list(adopt_entry(lib_op("Repair", TYPE_PROC_REF(/atom, cap_breakable_repair), OP_SHAPE_TOOL, using = repair_tool, key = "repair", kind = OP_STRUCTURAL, delay = repair_delay, needs = TYPE_PROC_REF(/atom, cap_breakable_is_broken), else_say = "it isn't broken", works_broken = TRUE, works_unpowered = TRUE, priority = OP_PRIORITY_PART), id = "breakable:[repair_tool]"))

/datum/capability/breakable/examine(atom/holder, mob/user)
	if(is_broken(holder))
		return list("It is broken.")
	return null

/datum/capability/breakable/draw(atom/holder, datum/look/look)
	draw_layer(look, when = is_broken(holder))

/datum/capability/breakable/ui_data(atom/holder, mob/user, list/data)
	data[LOOK_BROKEN] = is_broken(holder)

/// atom_break() / atom_fix() report here: a breakable holder mirrors it into CAP_BROKEN.
/atom/proc/caps_set_broken(broken)
	if(cap_of(src, /datum/capability/breakable))
		cap_set(src, CAP_BROKEN, broken)

/atom/proc/cap_breakable_is_broken(mob/user, obj/item/held)
	return is_broken(src)

/atom/proc/cap_breakable_repair(mob/user, obj/item/held)
	if(uses_integrity && get_integrity() < max_integrity)
		repair_damage(max_integrity - get_integrity()) // back above the failure point: atom_fix() runs
	cap_set(src, CAP_BROKEN, FALSE)
	act_message(user, src, self = "You repair %T%.", others = "%U% repairs %T%.")
	return TRUE

/**
 * Claws on a breakable machine, CAP_CLAW: an empty-handed swipe by an actor whose claws tear machines (req_claws()).
 * It is offered only where something hears the slash (req_heard(/datum/notice/slashed)), so on a machine nobody
 * listens to the touch stays whatever else it is. The op publishes /datum/notice/slashed; the holder's reaction
 * decides what gives. It wins over the holder's other empty-hand ops by its priority (OP_PRIORITY_CLAW: above taking
 * out what sits in an open bay).
 */
/proc/claw_op()
	return cap_op("Slash", TYPE_PROC_REF(/atom, claw_slash), using = EMPTY_HAND, offered = list(req_claws(), req_heard(/datum/notice/slashed)), key = CAP_CLAW, kind = OP_CONTROL, priority = OP_PRIORITY_CLAW, works_broken = TRUE, works_unpowered = TRUE)

/// The claw op's handler: the swipe lands (its cooldown, the noise, the prints) and the holder hears it.
/atom/proc/claw_slash(mob/living/carbon/human/user)
	user.setClickCooldown(user.get_attack_speed())
	act_message(user, src, self = span_notice("You slash at %T%!"), others = span_warning("%U% slashes at %T%!"))
	play_sfx(src, SFX_WEAPONS_SLASH, 2)
	add_hiddenprint(user)
	PUBLISH(src, /datum/notice/slashed, user)
	return TRUE
