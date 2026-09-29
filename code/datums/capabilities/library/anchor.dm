// anchor(): a tool fastens the holder to the floor or frees it. The atom's own `anchored` var is
// the truth (written through set_anchored()); there is no cap_state bit.
//
//	/obj/structure/thing/capabilities()
//		. = ..()
//		. += anchor(delay = 4 SECONDS)

/datum/capability/anchor
	log = LOG_GAME
	works_broken = TRUE
	works_unpowered = TRUE
	/// The TOOL_* quality that anchors and unanchors.
	var/tool_quality = TOOL_WRENCH
	/// Unscaled time the tool takes.
	var/delay = 2 SECONDS
	/// Refuse to anchor on space, open space, or anywhere that isn't a turf.
	var/needs_floor = TRUE

/proc/cap_anchor(tool = TOOL_WRENCH, delay = 2 SECONDS, needs_floor = TRUE, behind = NONE, log = LOG_GAME)
	var/datum/capability/anchor/C = new
	C.tool_quality = tool
	C.delay = delay
	C.needs_floor = needs_floor
	C.behind = behind
	C.log = log
	return C

/datum/capability/anchor/interactions(atom/holder)
	var/datum/capability/entry/wrapper = cap_tool("Anchor", tool_quality, TYPE_PROC_REF(/atom/movable, cap_anchor_toggle), delay = delay, behind = behind, needs = needs_floor ? TYPE_PROC_REF(/atom/movable, cap_anchor_floor_ok) : null, log = log, name_proc = TYPE_PROC_REF(/atom/movable, cap_anchor_name))
	return list(adopt_entry(wrapper))

/datum/capability/anchor/examine(atom/holder, mob/user)
	var/atom/movable/AM = holder
	if(!istype(AM))
		return null
	return list(AM.anchored ? "It is anchored." : "It is unanchored.")

/atom/movable/proc/cap_anchor_name(mob/user)
	return anchored ? "Unanchor" : "Anchor"

/// needs: unanchoring always works; anchoring wants a floor under it.
/atom/movable/proc/cap_anchor_floor_ok(mob/user, obj/item/held)
	if(anchored)
		return TRUE
	if(!isturf(loc))
		return "it has to be on the floor"
	if(isspace(loc) || isopenspace(loc))
		return "there's no floor to anchor it to"
	return TRUE

/atom/movable/proc/cap_anchor_toggle(mob/user, obj/item/held)
	set_anchored(!anchored)
	if(anchored)
		act_message(user, src, self = span_notice("You anchor %T%."), others = span_notice("%U% anchors %T%."), item = held)
	else
		act_message(user, src, self = span_notice("You unanchor %T%."), others = span_notice("%U% unanchors %T%."), item = held)
	return TRUE
