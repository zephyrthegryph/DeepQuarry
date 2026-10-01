// cap_buckle(): wraps the existing buckling system (code/game/objects/buckling.dm). Dragging a mob onto
// the holder buckles it through the movable's default drag interaction, which offers itself once
// can_buckle is set; these entries add buckling a mob held in a grab, and unbuckling.

/datum/capability/buckle
	layer_name = CAP_NO_LAYER

/**
 * Buckling entries. The buckling rules are the holder TYPE's own vars, which maps may vary per
 * instance (design review H1), so this writes nothing per instance: set can_buckle = TRUE,
 * max_buckled_mobs, buckle_lying and buckle_require_restraints on the type.
 */
/proc/cap_buckle(needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log = LOG_GAME)
	var/datum/capability/buckle/C = new
	return cap_gating(C, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)

#ifdef UNIT_TESTS
/datum/capability/buckle/on_holder_init(atom/holder, mapload)
	var/atom/movable/AM = holder
	if(istype(AM) && !initial(AM.can_buckle))
		stack_trace("[holder.type] declares cap_buckle() but its type doesn't set can_buckle = TRUE")
#endif

/datum/capability/buckle/interactions(atom/holder)
	// "unbuckle": with nobody buckled an empty hand did not mean it (the touch falls through).
	return list(
		adopt_entry(lib_op("Buckle", TYPE_PROC_REF(/atom/movable, cap_buckle_grabbed), OP_SHAPE_USE_ON, using = /obj/item/grab, key = "buckle", works_broken = TRUE, works_unpowered = TRUE)),
		adopt_entry(lib_op("Unbuckle", TYPE_PROC_REF(/atom/movable, cap_buckle_release), OP_SHAPE_HAND, key = "unbuckle", offered = req_proc(TYPE_PROC_REF(/atom/movable, cap_buckle_occupied), else_say = "nobody is buckled to it"), works_broken = TRUE, works_unpowered = TRUE)),
	)

/datum/capability/buckle/examine(atom/holder, mob/user)
	var/atom/movable/AM = holder
	if(!istype(AM) || !AM.has_buckled_mobs())
		return null
	var/list/names = list()
	for(var/mob/living/L as anything in AM.buckled_mob_list())
		names += "[L]"
	return list("[english_list(names)] [length(names) > 1 ? "are" : "is"] buckled to it.")

/atom/movable/proc/cap_buckle_occupied(mob/user, obj/item/held)
	return !!has_buckled_mobs()

/atom/movable/proc/cap_buckle_grabbed(mob/user, obj/item/grab/held)
	var/mob/living/M = held?.grab_target()
	if(!istype(M))
		return refuse(user, "You aren't holding anyone.")
	if(!user_buckle_mob(M, user))
		return UI_REFUSED // user_buckle_mob() said why
	return TRUE

/atom/movable/proc/cap_buckle_release(mob/user, obj/item/held)
	var/list/mobs = buckled_mob_list()
	var/mob/living/M
	if(length(mobs) == 1)
		M = mobs[1]
	else
		M = ask_mob(user, "Who do you wish to unbuckle?", mobs, "Unbuckle")
		if(!M || !(M in buckled_mob_list()))
			return UI_REFUSED
	if(!user_unbuckle_mob(M, user))
		return UI_REFUSED
	return TRUE
