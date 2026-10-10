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
	op("stuff_in", item(/mob/living/simple_mob), gesture(GESTURE_DRAG), priority(OP_PRIORITY_DEFAULT - 1), label("Put inside"), needs(req_adjacent()),
		starts(PROC_REF(stuffing_started)), begins(PROC_REF(stuffing_begins)), wait(2 SECONDS, keeps = STAY | ALIVE | TARGET_PRESENT), then(PROC_REF(stuffed)))
	op("release", hand(), label("Release"), then(PROC_REF(interaction_release)))
	op("stasis_cage_robot_release", remote(), when(req_actor_kind(/mob/living/silicon/robot)), label("Release"), then(PROC_REF(stasis_cage_robot_release)))

MSG_DEF_SELF(stasis_cage/needs_net, "It's going to be difficult to convince the creature to move into the cage without capturing it in a net.")

/// Only a creature caught in an energy net can be stuffed inside; Bumped() is what the old drag did first.
/obj/structure/stasis_cage/proc/stuffing_started(datum/act/op/A)
	var/mob/living/simple_mob/animal = A.held
	if(QDELETED(animal) || !istype(animal.buckled_to(), /obj/effect/energy_net))
		return /datum/msg/stasis_cage/needs_net
	animal.Bumped(A.actor)

/obj/structure/stasis_cage/proc/stuffing_begins(datum/act/op/A)
	return msg_text("You begin stuffing [A.held] into \the [src].", "%U% begins stuffing [A.held] into \the [src].")

/obj/structure/stasis_cage/proc/stuffed(datum/act/op/A)
	var/mob/living/simple_mob/animal = A.held
	if(QDELETED(animal))
		return OP_REFUSED
	act_message(A.actor, animal, MSG_SELF("You have stuffed %T% into \the [src]."), MSG_OTHERS("%U% has stuffed %T% into \the [src]."))
	contain(animal)
	return OP_OK

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

/// Relation view: contained (reads null once it is gone).
/obj/structure/stasis_cage/proc/contained() as /mob/living/simple_mob
	return contained
