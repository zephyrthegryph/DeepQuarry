/// Lighting queue ownership. Callers retain their existing needs_update gates;
/// appending here must preserve duplicates rather than silently deduplicate.
/datum/system/lighting/proc/queue_source(datum/light_source/source)
	sources_queue += source

/datum/system/lighting/proc/unqueue_source(datum/light_source/source)
	sources_queue -= source

/datum/system/lighting/proc/queue_corner(datum/lighting_corner/corner)
	corners_queue += corner

/datum/system/lighting/proc/unqueue_corner(datum/lighting_corner/corner)
	corners_queue -= corner

/datum/system/lighting/proc/queue_object(datum/lighting_object/object)
	objects_queue += object

/datum/system/lighting/proc/unqueue_object(datum/lighting_object/object)
	objects_queue -= object

/// Sleep/wake uses membership; visibility changes use the original append path.
/datum/system/lighting/proc/queue_sunlight(datum/sunlight_handler/handler, unique = FALSE)
	if(unique)
		sunlight_queue |= handler
	else
		sunlight_queue += handler

/datum/system/lighting/proc/unqueue_sunlight(datum/sunlight_handler/handler)
	sunlight_queue -= handler

/// Fake suns register their precomputed handler before requesting its update.
/datum/system/lighting/proc/register_sunlight_z(z, datum/planet_sunlight_handler/handler)
	if(z > length(z_to_pshandler))
		z_to_pshandler.len = z
	z_to_pshandler[z] = handler

/datum/system/lighting/proc/is_initialized()
	return initialized

/datum/system/lighting/proc/sunlight_scale()
	return sun_mult

/datum/system/lighting/proc/pending_source_count()
	return length(sources_queue)

/// The explosion benchmark waits for light propagation, not the sunlight pass.
/datum/system/lighting/proc/has_pending_light_updates()
	return length(sources_queue) || length(corners_queue) || length(objects_queue)

/datum/system/lighting/proc/completed_steps()
	return times_fired
