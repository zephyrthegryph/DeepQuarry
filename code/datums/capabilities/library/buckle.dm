// buckle(): wraps the existing buckling system (code/game/objects/buckling.dm). Dragging a mob onto
// the holder buckles it through the movable's default drag interaction, which offers itself once
// can_buckle is set; these entries add buckling a mob held in a grab, and unbuckling.

/datum/capability/buckle
	log = LOG_GAME
	works_broken = TRUE
	works_unpowered = TRUE
	/// How many mobs can be buckled at once (max_buckled_mobs).
	var/max = 1
	/// Buckled mobs lie down (a bed) instead of sitting up (a chair).
	var/lying = FALSE
	/// Only restrained mobs can be buckled (pipes).
	var/needs_restraints = FALSE

/proc/cap_buckle(max = 1, lying = FALSE, needs_restraints = FALSE, behind = NONE, log = LOG_GAME)
	var/datum/capability/buckle/C = new
	C.max = max
	C.lying = lying
	C.needs_restraints = needs_restraints
	C.behind = behind
	C.log = log
	return C

/datum/capability/buckle/on_holder_init(atom/holder, mapload)
	var/atom/movable/AM = holder
	if(!istype(AM))
		return
	// The args are type defaults (design review H1): a map varedit of these holder vars wins.
	AM.can_buckle = TRUE
	if(AM.max_buckled_mobs == initial(AM.max_buckled_mobs))
		AM.max_buckled_mobs = max
	if(AM.buckle_lying == initial(AM.buckle_lying))
		AM.buckle_lying = lying ? 1 : 0
	if(AM.buckle_require_restraints == initial(AM.buckle_require_restraints))
		AM.buckle_require_restraints = needs_restraints

/datum/capability/buckle/interactions(atom/holder)
	var/datum/capability/entry/grabbed = cap_use_on("Buckle", /obj/item/grab, TYPE_PROC_REF(/atom/movable, cap_buckle_grabbed), behind = behind, works_broken = TRUE, works_unpowered = TRUE, log = log)
	var/datum/capability/entry/release = cap_hand("Unbuckle", TYPE_PROC_REF(/atom/movable, cap_buckle_release), behind = behind, needs = TYPE_PROC_REF(/atom/movable, cap_buckle_occupied), else_say = "nobody is buckled to it", works_broken = TRUE, works_unpowered = TRUE, log = log)
	return list(adopt_entry(grabbed), adopt_entry(release))

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
