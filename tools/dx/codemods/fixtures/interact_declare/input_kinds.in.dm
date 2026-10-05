DECLARE_INTERACTIONS(/obj/machinery/gap_cell, \
	INTERACT_DRAG("Put inside", PROC_REF(interaction_drag)), \
	INTERACT_ALT("Flip the switch", PROC_REF(interaction_alt)), \
	INTERACT_TK(null, PROC_REF(interaction_tk)), \
	INTERACT_SELF(null, PROC_REF(interaction_self)), \
)

/obj/machinery/gap_cell/proc/interaction_drag(mob/user, mob/living/target, datum/interaction/interaction)
	if(!ismob(target) || user.lying)
		return FALSE
	put_mob(target, user)
	return TRUE

/obj/machinery/gap_cell/proc/interaction_alt(mob/user, obj/item/held, datum/interaction/interaction)
	if(!powered)
		return FALSE
	flip(user)
	return TRUE

/obj/machinery/gap_cell/proc/interaction_tk(mob/user, obj/item/held, datum/interaction/interaction)
	if(!powered)
		return FALSE
	nudge(user)
	return TRUE

/obj/machinery/gap_cell/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(!powered)
		return FALSE
	return TRUE
