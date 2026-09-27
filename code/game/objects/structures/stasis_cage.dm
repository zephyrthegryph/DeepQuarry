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

	var/mob/living/simple_mob/A = locate() in loc
	if(A)
		contain(A)

/obj/structure/stasis_cage/attack_hand(mob/user)
	release()

/obj/structure/stasis_cage/attack_robot(mob/user)
	if(Adjacent(user))
		release()

/obj/structure/stasis_cage/proc/contain(mob/living/simple_mob/animal)
	if(contained || !istype(animal))
		return

	contained = animal
	animal.forceMove(src)
	animal.set_stasis(/datum/modifier/stasis/total, src)
	if(animal?.buckled_to() && istype(animal?.buckled_to(), /obj/effect/energy_net))
		var/atom/movable/_tmp_buck_11 = animal?.buckled_to()
		_tmp_buck_11.forceMove(animal.loc)
	icon_state = "critter"
	desc = initial(desc) + " \The [contained] is kept inside."

/obj/structure/stasis_cage/proc/release()
	if(!contained)
		return

	contained.dropInto(src)
	if(contained?.buckled_to() && istype(contained?.buckled_to(), /obj/effect/energy_net))
		var/atom/movable/_tmp_buck_12 = contained?.buckled_to()
		_tmp_buck_12.dropInto(src)
	contained.set_stasis(null, src)
	contained = null
	icon_state = "critteropen"
	underlays.Cut()
	desc = initial(desc)

// LIFECYCLE: the caged creature is released.
/obj/structure/stasis_cage/Destroy()
	release()

	return ..()

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
		om_do_after(user, 2 SECONDS, target = over_object, receiver = src, on_done = PROC_REF(MouseDrop_timed_done), done_args = list(over_object, user))
	else
		return ..()

/mob/living/simple_mob/proc/MouseDrop_timed_done(obj/structure/stasis_cage/over_object, mob/user)
	user.visible_message("[user] has stuffed \the [src] into \the [over_object].", "You have stuffed \the [src] into \the [over_object].")
	over_object.contain(src)
