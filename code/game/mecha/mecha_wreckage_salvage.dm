/**
 * Exosuit wreckage salvage (the ops are in the wreckage's CAPABILITIES list, mecha_wreckage.dm).
 *
 * Each salvage op leaves the wreck as it is and runs out with the wreck's salvage. A welder cuts sheets, rods or parts (a 70% chance
 * each time), wirecutters cut cable (70%), a crowbar pries out what the wreck held.
 */

MSG_DEF_SELF(mecha_wreckage/nothing_to_cut_with, "You don't see anything that can be cut with %I%.")
MSG_DEF_SELF(mecha_wreckage/nothing_to_cut, "There is nothing left to cut.")
MSG_DEF_SELF(mecha_wreckage/nothing_to_pry, "You don't see anything that can be pried out.")

/obj/effect/decal/mecha_wreckage/proc/has_salvage_left(datum/act/A)
	return read_once(salvage_num > 0) ? null : MSG(req_failed)

/obj/effect/decal/mecha_wreckage/proc/has_welder_salvage(datum/act/A)
	return read_once(length(welder_salvage) > 0) ? null : MSG(req_failed)

/obj/effect/decal/mecha_wreckage/proc/has_pry_salvage(datum/act/A)
	return read_once(length(crowbar_salvage) > 0) ? null : MSG(req_failed)

/obj/effect/decal/mecha_wreckage/proc/cut_salvage(datum/act/op/A)
	var/mob/user = A.actor
	var/type = prob(70) ? pick(welder_salvage) : null
	if(!type)
		to_chat(user, "You failed to salvage anything valuable from [src].")
		return OP_OK
	var/N = new type(get_turf(user))
	act_message(user, src, MSG_SELF("You cut [N] from %T%"), MSG_OTHERS("%U% cuts [N] from %T%"), MSG_BLIND("You hear a sound of welder nearby"))
	if(istype(N, /obj/item/mecha_parts/part))
		welder_salvage -= type
	salvage_num--
	return OP_OK

/obj/effect/decal/mecha_wreckage/proc/snip_salvage(datum/act/op/A)
	var/mob/user = A.actor
	if(isemptylist(wirecutters_salvage))
		return OP_OK
	var/type = prob(70) ? pick(wirecutters_salvage) : null
	if(!type)
		to_chat(user, "You failed to salvage anything valuable from [src].")
		return OP_OK
	var/N = new type(get_turf(user))
	act_message(user, src, MSG_SELF("You cut [N] from %T%."), MSG_OTHERS("%U% cuts [N] from %T%."))
	salvage_num--
	return OP_OK

/obj/effect/decal/mecha_wreckage/proc/pry_salvage(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/S = pick(crowbar_salvage)
	if(!S)
		return OP_OK
	S.forceMove(get_turf(user))
	rel_remove(src, nameof(crowbar_salvage), S)
	act_message(user, S, MSG_SELF("You pry %T% from [src]."), MSG_OTHERS("%U% pries %T% from [src]."))
	return OP_OK
