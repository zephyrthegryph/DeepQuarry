/obj/structure/stasis_cage
	name = "stasis cage"
	desc = "A high-tech animal cage, designed to keep contained fauna docile and safe."
	icon = 'icons/obj/storage_vr.dmi'
	icon_state = "critteropen"
	density = TRUE
	unacidable = TRUE

	var/mob/living/simple_mob/contained

/obj/structure/stasis_cage/Initialize(mapload)
	. = ..()

	var/mob/living/simple_mob/A = locate_within(loc, /mob/living/simple_mob)
	if(A)
		contain(A)

CAPABILITIES(/obj/structure/stasis_cage)
	op("release", hand(), label("Release"), then(PROC_REF(interaction_release)))
	op("stasis_cage_robot_release", remote(), when(req_actor_kind(/mob/living/silicon/robot)), label("Release"), then(PROC_REF(stasis_cage_robot_release)))

/obj/structure/stasis_cage/proc/interaction_release(datum/act/op/A)
	release()
	return TRUE

/// Old attack_robot: a cyborg next to it releases the animal.
/obj/structure/stasis_cage/proc/stasis_cage_robot_release(datum/act/op/A)
	var/mob/user = A.actor
	if(Adjacent(user))
		release()
	return TRUE

/obj/structure/stasis_cage/proc/contain(mob/living/simple_mob/animal)
	if(contained() || !istype(animal))
		return

	rel_set(src, nameof(contained), animal)
	animal.forceMove(src)
	animal.set_stasis(/datum/body_effect/stasis/total, src)
	if(animal?.buckled_to() && istype(animal?.buckled_to(), /obj/effect/energy_net))
		var/atom/movable/_tmp_buck_11 = animal?.buckled_to()
		_tmp_buck_11.forceMove(animal.loc)
	icon_state = "critter"
	desc = initial(desc) + " \The [contained()] is kept inside."

/obj/structure/stasis_cage/proc/release()
	if(!contained())
		return

	contained().dropInto(src)
	if(contained()?.buckled_to() && istype(contained()?.buckled_to(), /obj/effect/energy_net))
		var/atom/movable/_tmp_buck_12 = contained()?.buckled_to()
		_tmp_buck_12.dropInto(src)
	contained().set_stasis(null, src)
	rel_clear(src, nameof(contained))
	icon_state = "critteropen"
	underlays.Cut()
	desc = initial(desc)

// the caged creature is released.
/obj/structure/stasis_cage/on_destroy(force)
	release()

	..()

/mob/living/simple_mob/MouseDrop(obj/structure/stasis_cage/over_object)
	var/mob/user = usr
	if(!istype(user))
		return
	if(istype(over_object) && Adjacent(over_object) && CanMouseDrop(over_object, user))

		if(!src?.buckled_to() || !istype(src?.buckled_to(), /obj/effect/energy_net))
			to_chat(user, "It's going to be difficult to convince \the [src] to move into \the [over_object] without capturing it in a net.")
			return

		act_message(user, src, MSG_SELF("You begin stuffing %T% into \the [over_object]."), MSG_OTHERS("%U% begins stuffing %T% into \the [over_object]."))
		Bumped(user)
		task_timed(user, 2 SECONDS, target = over_object, receiver = src, on_done = PROC_REF(MouseDrop_timed_done), done_args = list(over_object, user))
	else
		return ..()

/mob/living/simple_mob/proc/MouseDrop_timed_done(obj/structure/stasis_cage/over_object, mob/user)
	act_message(user, src, MSG_SELF("You have stuffed %T% into \the [over_object]."), MSG_OTHERS("%U% has stuffed %T% into \the [over_object]."))
	over_object.contain(src)

/// Relation view: contained (reads null once it is gone).
/obj/structure/stasis_cage/proc/contained() as /mob/living/simple_mob
	return contained
