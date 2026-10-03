/datum/mini_hud
	var/datum/hud/main_hud
	/// Our screen elements (owned)
	var/list/screenobjs

CAPABILITIES(/datum/mini_hud)
	owns_many(nameof(screenobjs))

/// Subtypes that update every second set this: periodic_step() runs while it is (DECLARE_PERIODIC_WHILE).
OM_FIELD(/datum/mini_hud, needs_processing, FALSE, CHANGE_DATUM_A)
DECLARE_PERIODIC_WHILE(/datum/mini_hud, PERIODIC_SECOND, "needs_processing")

/datum/mini_hud/New(datum/hud/other)
	..()
	apply_to_hud(other)
	lifecycle_decls_init(src) // starts the declaration (a non-atom has no materialize)


// takes itself off the hud it was applied to.
/datum/mini_hud/on_destroy(force)
	unapply_to_hud()
	..()

// Apply to a real /datum/hud
/datum/mini_hud/proc/apply_to_hud(datum/hud/other)
	if(main_hud())
		unapply_to_hud(main_hud())
	rel_set(src, nameof(main_hud), other)
	main_hud().apply_minihud(src)

// Remove from a real /datum/hud
/datum/mini_hud/proc/unapply_to_hud()
	main_hud()?.remove_minihud(src)
	rel_clear(src, nameof(main_hud))

// Update the hud
/datum/mini_hud/periodic_step()
	return PROCESS_KILL // You shouldn't be here!

// Return a list of screen objects we use
/datum/mini_hud/proc/get_screen_objs(mob/M)
	return screenobjs ? screenobjs.Copy() : list()

/// The hud this mini hud is applied to (a relation view: null once that is deleted).
/datum/mini_hud/proc/main_hud() as /datum/hud
	return main_hud
