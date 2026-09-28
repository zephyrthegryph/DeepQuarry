/datum/mini_hud
	var/main_hud_handle
	var/list/screenobjs
	var/needs_processing = FALSE

/datum/mini_hud/New(datum/hud/other)
	apply_to_hud(other)
	if(needs_processing)
		PERIODIC_START(src, PERIODIC_SECOND)

REF_OWNED_LIST(/datum/mini_hud, "screenobjs")

// takes itself off the hud it was applied to.
/datum/mini_hud/on_destroy(force)
	unapply_to_hud()
	..()

// Apply to a real /datum/hud
/datum/mini_hud/proc/apply_to_hud(datum/hud/other)
	if(main_hud())
		unapply_to_hud(main_hud())
	main_hud_handle = om_handle(other)
	main_hud().apply_minihud(src)

// Remove from a real /datum/hud
/datum/mini_hud/proc/unapply_to_hud()
	main_hud()?.remove_minihud(src)
	main_hud_handle = null

// Update the hud
/datum/mini_hud/periodic_step()
	return PROCESS_KILL // You shouldn't be here!

// Return a list of screen objects we use
/datum/mini_hud/proc/get_screen_objs(mob/M)
	return screenobjs.Copy()

/// LC-refs: the hud this mini hud is applied to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/mini_hud/proc/main_hud() as /datum/hud
	return om_resolve(main_hud_handle)
