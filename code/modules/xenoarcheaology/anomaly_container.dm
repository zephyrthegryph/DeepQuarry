/obj/structure/anomaly_container
	name = "anomaly container"
	desc = "Used to safely contain and move anomalies."
	icon = 'icons/obj/xenoarchaeology.dmi'
	icon_state = "anomaly_container"
	density = TRUE

	var/tmp/obj/machinery/artifact/contained

// ALLOW(init/INSTANCE_STATE): takes in the artifact the map placed on its tile
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

CAPABILITIES(/obj/structure/anomaly_container)
	op("hand", hand(), ungated(), label("Use"), then(PROC_REF(interaction_hand)))
	op("anomaly_container_robot_release", remote(), when(req(/mob/living/silicon/robot, of = ON_ACTOR)), label("Release"), then(PROC_REF(anomaly_container_robot_release)))

/// Old attack_hand.
/obj/structure/anomaly_container/proc/interaction_hand(datum/act/op/A)
	release()
	return TRUE

/// Old attack_robot: an adjacent cyborg releases the contents. Never fell through.
/obj/structure/anomaly_container/proc/anomaly_container_robot_release(datum/act/op/A)
	var/mob/user = A.actor
	if(Adjacent(user))
		release()
	return TRUE

/obj/structure/anomaly_container/proc/contain(obj/machinery/artifact/artifact)
	if(contained())
		return
	rel_set(src, nameof(contained), artifact)
	artifact.forceMove(src)
	underlays += image(artifact)
	desc = "Used to safely contain and move anomalies. \The [contained()] is kept inside."

/obj/structure/anomaly_container/proc/release()
	if(!contained())
		return
	contained().dropInto(src)
	rel_clear(src, nameof(contained))
	underlays.Cut()
	desc = initial(desc)

/atom/MouseDrop(obj/structure/anomaly_container/over_object)
	. = ..()

	if(istype(over_object))
		if(!QDELETED(src) && isturf(loc) && is_anomalous() && Adjacent(over_object) && CanMouseDrop(over_object, usr))
			Bumped(usr)
			over_object.contain(src)

/// Accessor for the contained var.
/obj/structure/anomaly_container/proc/contained() as /obj/machinery/artifact
	return contained
