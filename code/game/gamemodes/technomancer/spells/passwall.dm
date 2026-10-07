/datum/technomancer/spell/passwall
	name = "Passwall"
	desc = "An uncommon function that allows the user to phase through matter (usually walls) in order to enter or exit a room.  Be careful you don't pass into \
	somewhere dangerous."
	enhancement_desc = "Cost per tile is halved."
	cost = 100
	obj_path = /obj/item/spell/passwall
	ability_icon_state = "tech_passwall"
	category = UTILITY_SPELLS

/obj/item/spell/passwall
	name = "passwall"
	desc = "No walls can hold you back."
	cast_methods = CAST_MELEE
	aspect = ASPECT_TELE
	var/maximum_distance = 20 //Measured in tiles.

/obj/item/spell/passwall/on_melee_cast(atom/hit_atom, mob/user)
	if(task_busy(src))	//Prevent someone from trying to get two uses of the spell from one instance.
		return 0
	if(!allowed_to_teleport())
		to_chat(user, span_warning("You can't teleport here!"))
		return 0

	var/turf/T = get_turf(hit_atom)		//Turf we touched.
	var/turf/our_turf = get_turf(user)	//Where we are.
	if(!T.density)
		if(!T.check_density())
			to_chat(user, span_warning("Perhaps you should try using passWALL on a wall, or other solid object."))
			return 0
	var/direction = get_dir(our_turf, T)
	var/total_cost = 0
	var/turf/checked_turf = T			//Turf we're currently checking for density in the loop below.
	var/turf/found_turf = null			//Our destination, if one is found.
	var/i = maximum_distance

	act_message(user, hit_atom, others = span_info("%U% rests a hand on %T%."))

	while(i)
		checked_turf = get_step(checked_turf, direction) //Advance in the given direction
		total_cost += check_for_scepter() ? 400 : 800 //Phasing through matter's expensive, you know.
		i--
		if(checked_turf.block_tele) // The fun ends here.
			break

		if(!checked_turf.density) //If we found a destination (a non-dense turf), then we can stop.
			var/dense_objs_on_turf = 0
			for(var/atom/movable/stuff in turf_contents_of_type(checked_turf, /atom/movable)) //Make sure nothing dense is where we want to go, like an airlock or window.
				if(stuff.density)
					dense_objs_on_turf = 1

			if(!dense_objs_on_turf) //If we found a non-dense turf with nothing dense on it, then that's our destination.
				found_turf = checked_turf
				break

	// The search takes a second per tile checked; the spell is busy (a hold claims it) meanwhile.
	var/search_time = (maximum_distance - i) SECONDS
	task_hold_busy(src, search_time)
	after(src, search_time, PROC_REF(passwall_found), with = list(user, hit_atom, our_turf, found_turf, total_cost))
	return 1

/obj/item/spell/passwall/proc/passwall_found(mob/living/user, atom/hit_atom, turf/our_turf, turf/found_turf, total_cost)
	if(QDELETED(user))
		return
	if(found_turf)
		if(user.loc != our_turf)
			to_chat(user, span_warning("You need to stand still in order to phase through \the [hit_atom]."))
			return 0
		if(pay_energy(total_cost) && !user.incapacitated() )
			act_message(user, hit_atom, others = span_warning("%U% appears to phase through %T%!"))
			to_chat(user, span_info("You find a destination on the other side of \the [hit_atom], and phase through it."))
			fx_sparks(our_turf, 5, FALSE)
			user.forceMove(found_turf)
			consume(src, user)
			return 1
		else
			to_chat(user, span_warning("You don't have enough energy to phase through these walls!"))
	else
		to_chat(user, span_info("You weren't able to find an open space to go to."))
