// CAMERA NET
//
// The datum containing all the chunks.

/datum/visualnet/camera
	chunk_type = /datum/chunk/camera

/// Sorts the camera registry once, the first time a sorted view is needed.
/datum/visualnet/camera/proc/process_sort()
	var/datum/registry/cameras/registry = get_registry(REGISTRY_CAMERAS)
	registry.sort()

// Removes a camera from a chunk.

/datum/visualnet/camera/proc/removeCamera(obj/machinery/camera/c)
	if(c.can_use())
		majorChunkChange(c, 0)

// Add a camera to a chunk.

/datum/visualnet/camera/proc/addCamera(obj/machinery/camera/c)
	if(c.can_use())
		majorChunkChange(c, 1)

// Used for Cyborg cameras. Since portable cameras can be in ANY chunk.

/datum/visualnet/camera/proc/updatePortableCamera(obj/machinery/camera/c)
	if(c.can_use())
		majorChunkChange(c, 1)
	//else
	//	majorChunkChange(c, 0)

/datum/visualnet/camera/onMajorChunkChange(atom/c, choice, datum/chunk/camera/chunk)
// Only add actual cameras to the list of cameras
	if(istype(c, /obj/machinery/camera))
		if(choice == 0)
			// Remove the camera.
			chunk.cameras -= c
		else if(choice == 1)
			// You can't have the same camera in the list twice.
			chunk.cameras |= c
