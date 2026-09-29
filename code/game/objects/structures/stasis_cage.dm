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

/obj/structure/stasis_cage/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_hand/stasis_cage_release,
	)
	into += dq_interaction_from_spec(type, INTERACT_ROBOT("Release", PROC_REF(stasis_cage_robot_release)))
	..()

/// Old attack_hand: release the contained animal.
/datum/interaction/entry_hand/stasis_cage_release
	id = "stasis_cage_release"
	name = "Release"
	effect = /obj/structure/stasis_cage/proc/interaction_release

/obj/structure/stasis_cage/proc/interaction_release(mob/user, obj/item/held, datum/interaction/interaction)
	release()
	return TRUE

/// Old attack_robot: a cyborg next to it releases the animal.
/obj/structure/stasis_cage/proc/stasis_cage_robot_release(mob/user, obj/item/held, datum/interaction/interaction)
	if(Adjacent(user))
		release()
	return TRUE

/obj/structure/stasis_cage/proc/contain(mob/living/simple_mob/animal)
	if(contained() || !istype(animal))
		return

	rel_set(src, "contained", animal)
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
	rel_clear(src, "contained")
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

		user.visible_message("[user] begins stuffing \the [src] into \the [over_object].", "You begin stuffing \the [src] into \the [over_object].")
		Bumped(user)
		om_task_timed(user, 2 SECONDS, target = over_object, receiver = src, on_done = PROC_REF(MouseDrop_timed_done), done_args = list(over_object, user))
	else
		return ..()

/mob/living/simple_mob/proc/MouseDrop_timed_done(obj/structure/stasis_cage/over_object, mob/user)
	user.visible_message("[user] has stuffed \the [src] into \the [over_object].", "You have stuffed \the [src] into \the [over_object].")
	over_object.contain(src)

/// Relation view: contained (reads null once it is gone).
/obj/structure/stasis_cage/proc/contained() as /mob/living/simple_mob
	return contained
