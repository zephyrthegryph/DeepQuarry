//Removing the lock and the buttons.
/obj/item/gun/dropped(mob/living/user)
	if(istype(user))
		user.stop_aiming(src)
	return ..()

/obj/item/gun/equipped(mob/living/user, slot)
	if(istype(user) && (slot != SLOT_ID_HAND_L && slot != SLOT_ID_HAND_R))
		user.stop_aiming(src)
	return ..()

//Compute how to fire.....
//Return 1 if a target was found, 0 otherwise.
/obj/item/gun/proc/PreFire(atom/A, mob/living/user, params)
	if(!user.aiming)
		own_set(user, "aiming", new /obj/aiming_overlay(user))
	user.face_atom(A)
	if(ismob(A) && user.aiming)
		user.aiming.aim_at(A, src)
		if(!isliving(A) || A.is_incorporeal()) // Phase out can't be targetted when phased
			return 0
		return 1
	return 0
