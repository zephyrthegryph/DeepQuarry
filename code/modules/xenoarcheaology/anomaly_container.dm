/obj/structure/anomaly_container
	name = "anomaly container"
	desc = "Used to safely contain and move anomalies."
	icon = 'icons/obj/xenoarchaeology.dmi'
	icon_state = "anomaly_container"
	density = TRUE

	var/tmp/contained_handle

/obj/structure/anomaly_container/Initialize(mapload)
	. = ..()

	var/obj/machinery/artifact/A = locate_within(loc, /obj/machinery/artifact)
	if(A)
		contain(A)

	else
		for(var/obj/Ob in contents_of(loc))
			if(can_contain(Ob))
				contain(Ob)
				break

/obj/structure/anomaly_container/proc/can_contain(obj/O)
	return O.is_anomalous()

DECLARE_INTERACTIONS(/obj/structure/anomaly_container, \
	INTERACT_HAND_UNGATED(null, PROC_REF(interaction_hand)), \
	INTERACT_ROBOT("Release", PROC_REF(anomaly_container_robot_release)), \
)

/// Old attack_hand.
/obj/structure/anomaly_container/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	release()
	return TRUE

/// Old attack_robot: an adjacent cyborg releases the contents. Never fell through.
/obj/structure/anomaly_container/proc/anomaly_container_robot_release(mob/user, obj/item/held, datum/interaction/interaction)
	if(Adjacent(user))
		release()
	return TRUE

/obj/structure/anomaly_container/proc/contain(obj/machinery/artifact/artifact)
	if(contained())
		return
	contained_handle = om_handle(artifact)
	artifact.forceMove(src)
	underlays += image(artifact)
	desc = "Used to safely contain and move anomalies. \The [contained()] is kept inside."

/obj/structure/anomaly_container/proc/release()
	if(!contained())
		return
	contained().dropInto(src)
	contained_handle = null
	underlays.Cut()
	desc = initial(desc)

/atom/MouseDrop(obj/structure/anomaly_container/over_object)
	. = ..()

	if(istype(over_object))
		if(!QDELETED(src) && isturf(loc) && is_anomalous() && Adjacent(over_object) && CanMouseDrop(over_object, usr))
			Bumped(usr)
			over_object.contain(src)

/// LC-refs: the contained this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/structure/anomaly_container/proc/contained() as /obj/machinery/artifact
	return om_resolve(contained_handle)
