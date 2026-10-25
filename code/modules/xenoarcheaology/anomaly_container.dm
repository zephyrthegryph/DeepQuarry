/obj/structure/anomaly_container
	name = "anomaly container"
	desc = "Used to safely contain and move anomalies."
	icon = 'icons/obj/xenoarchaeology.dmi'
	icon_state = "anomaly_container"
	density = TRUE

	var/tmp/obj/machinery/artifact/contained

/// Capture the map-placed occupant after the container itself is initialized.
/obj/structure/anomaly_container/proc/contain_initial_anomaly()

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
	setup(PROC_REF(contain_initial_anomaly))
	op("hand", hand(), ungated(), label("Use"), then(PROC_REF(interaction_hand)))
	op("anomaly_container_robot_release", remote(), when(req(/mob/living/silicon/robot, of = ON_ACTOR)), label("Release"), then(PROC_REF(anomaly_container_robot_release)))
	ref_one(nameof(contained))
	op("contain_anomaly", item(/obj), gesture(GESTURE_DRAG), label("Contain"), when(req(PROC_REF(anomaly_dragged))), then(PROC_REF(anomaly_contained)))

/// Only an anomalous thing on the floor within the actor's reach is dragged in (the old MouseDrop's guard).
/obj/structure/anomaly_container/proc/anomaly_dragged(datum/act/op/A)
	var/obj/dragged = A.held
	if(!istype(dragged) || QDELETED(dragged) || !isturf(dragged.loc) || !dragged.is_anomalous())
		return /datum/msg/req_failed
	if(!read_once(dragged.Adjacent(src) && dragged.CanMouseDrop(src, A.actor)))
		return /datum/msg/req_failed
	return null

/// An anomaly dragged onto the container: it bumps the dragger, then goes in.
/obj/structure/anomaly_container/proc/anomaly_contained(datum/act/op/A)
	var/obj/machinery/artifact/dragged = A.held
	dragged.Bumped(A.actor)
	contain(dragged)
	return OP_OK

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

/// Accessor for the contained var.
/obj/structure/anomaly_container/proc/contained() as /obj/machinery/artifact
	return contained
