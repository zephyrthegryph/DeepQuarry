// anchor(): a tool fastens the holder to the floor or frees it. The atom's own `anchored` var is
// the truth (written through set_anchored()); there is no cap_state bit.
//
//	/obj/structure/thing/capabilities()
//		. = ..()
//		. += cap_anchor(delay = 4 SECONDS)

/datum/capability/anchor
	layer_name = CAP_NO_LAYER
	/// The TOOL_* quality that anchors and unanchors.
	var/tool_quality = TOOL_WRENCH
	/// Unscaled time the tool takes.
	var/delay = 2 SECONDS
	/// Refuse to anchor on space, open space, or anywhere that isn't a turf.
	var/needs_floor = TRUE

/proc/cap_anchor(tool = TOOL_WRENCH, delay = 2 SECONDS, needs_floor = TRUE, behind = NONE, blocked_by = NONE, locked_by = NONE, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log = LOG_GAME, layer = CAP_NO_LAYER)
	var/datum/capability/anchor/C = new
	C.tool_quality = tool
	C.delay = delay
	C.needs_floor = needs_floor
	C.layer_name = layer
	return cap_gating(C, behind = behind, blocked_by = blocked_by, locked_by = locked_by, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)

/datum/capability/anchor/interactions(atom/holder)
	return list(adopt_entry(cap_tool("Anchor", tool_quality, GLOBAL_PROC_REF(cap_anchor_toggle), delay = delay, needs = needs_floor ? GLOBAL_PROC_REF(cap_anchor_floor_ok) : null, name_proc = GLOBAL_PROC_REF(cap_anchor_name))))

/datum/capability/anchor/examine(atom/holder, mob/user)
	var/atom/movable/AM = holder
	if(!istype(AM))
		return null
	return list(AM.anchored ? "It is anchored." : "It is unanchored.")

/proc/cap_anchor_name(atom/movable/holder, mob/user)
	return holder.anchored ? "Unanchor" : "Anchor"

/// needs: unanchoring always works; anchoring wants a floor under it.
/proc/cap_anchor_floor_ok(mob/user, atom/movable/holder, obj/item/held)
	if(holder.anchored)
		return TRUE
	if(!isturf(holder.loc))
		return "it has to be on the floor"
	if(isspace(holder.loc) || isopenspace(holder.loc))
		return "there's no floor to anchor it to"
	return TRUE

/proc/cap_anchor_toggle(atom/movable/holder, mob/user, obj/item/held)
	holder.set_anchored(!holder.anchored)
	if(holder.anchored)
		act_message(user, holder, self = span_notice("You anchor %T%."), others = span_notice("%U% anchors %T%."), item = held)
	else
		act_message(user, holder, self = span_notice("You unanchor %T%."), others = span_notice("%U% unanchors %T%."), item = held)
	return TRUE
