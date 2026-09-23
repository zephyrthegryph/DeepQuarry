#define BORG_CAMERA_BUFFER 30

// ROBOT MOVEMENT

// Update the portable camera everytime the Robot moves.
// This might be laggy, comment it out if there are problems.
/mob/living/silicon/var/updating = 0

/mob/living/silicon/robot/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	if(!provides_camera_vision())
		return
	if(!updating)
		updating = 1
		spawn(BORG_CAMERA_BUFFER)
			if(old_loc != src.loc)
				GLOB.cameranet.updatePortableCamera(src.camera)
			updating = 0

/mob/living/silicon/ai/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	if(!provides_camera_vision())
		return
	if(!updating)
		updating = 1
		spawn(BORG_CAMERA_BUFFER)
			if(old_loc != src.loc)
				GLOB.cameranet.updateVisibility(old_loc, 0)
				GLOB.cameranet.updateVisibility(loc, 0)
			updating = 0

#undef BORG_CAMERA_BUFFER

// CAMERA

// An addition to deactivate which removes/adds the camera from the chunk list based on if it works or not.

/obj/machinery/camera/deactivate(user as mob, choice = 1)
	..(user, choice)
	if(src.can_use())
		GLOB.cameranet.addCamera(src)
	else
		src.set_light(0)
		GLOB.cameranet.removeCamera(src)

REGISTRY_MEMBERSHIP(/obj/machinery/camera, REGISTRY_CAMERAS)

/// Joins the camera net (L3): the registry join above lists it, this covers chunks.
/obj/machinery/camera/on_materialize()
	. = ..()
	update_coverage(1)

/obj/machinery/camera/on_dematerialize()
	// QDELETING cameras fail can_use(), so removeCamera() would be a no-op.
	// Remove the camera from every chunk directly; otherwise each covered chunk
	// retains a hard reference.
	GLOB.cameranet.majorChunkChange(src, 0)
	on_open_network = 0
	return ..()

/obj/machinery/camera/Destroy()
	clear_all_networks()
	return ..()

// Mobs
/mob/living/silicon/ai/rejuvenate()
	var/was_dead = stat == DEAD
	..()
	if(was_dead && stat != DEAD)
		// Arise!
		GLOB.cameranet.updateVisibility(src, 0)

/mob/living/silicon/ai/death(gibbed)
	if(..())
		// If true, the mob went from living to dead (assuming everyone has been overriding as they should...)
		GLOB.cameranet.updateVisibility(src, 0)
