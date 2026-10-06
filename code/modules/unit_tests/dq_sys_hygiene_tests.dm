// Hygiene wave (doc/rewrite/systems.md, "Hygiene"): declared caches, shared caches and
// after() deadlines that replaced hand-maintained cached_* vars and world.time polling.

/// A choiced preference's possible values come from one shared cache per type, not a per-instance var.
/datum/unit_test/dq_sys_hygiene_preference_choices

/datum/unit_test/dq_sys_hygiene_preference_choices/Run()
	var/datum/preference/choiced/species/pref = GLOB.preference_entries[/datum/preference/choiced/species]
	TEST_ASSERT(istype(pref), "no species preference entry")
	var/list/first = pref.get_choices()
	TEST_ASSERT(length(first), "species preference has no choices")
	TEST_ASSERT(first == pref.get_choices(), "get_choices() rebuilt its list instead of reading the shared cache")

/// An asset's serialized URL mappings are a declared cache: CHANGE_EXPLICIT clears them.
/datum/unit_test/dq_sys_hygiene_asset_declared_cache

/datum/unit_test/dq_sys_hygiene_asset_declared_cache/Run()
	var/datum/asset/A = get_asset_datum(/datum/asset/simple/generic)
	TEST_ASSERT(istype(A), "no generic asset datum")
	var/message = A.get_serialized_url_mappings()
	TEST_ASSERT(!isnull(message), "serialized mappings were not built")
	TEST_ASSERT(!isnull(A.cached_serialized_url_mappings), "serialized mappings were not kept")
	changed(A, CHANGE_EXPLICIT)
	TEST_ASSERT(isnull(A.cached_serialized_url_mappings), "CHANGE_EXPLICIT did not clear the declared cache")
	TEST_ASSERT(isnull(A.cached_serialized_url_mappings_transport_type), "CHANGE_EXPLICIT did not clear the transport key")
	TEST_ASSERT(!isnull(A.get_serialized_url_mappings()), "serialized mappings were not rebuilt after clearing")

/// The anomaly device's run ends on its after() timer, not a world.time check in its step.
/datum/unit_test/dq_sys_hygiene_anodevice_timer

/datum/unit_test/dq_sys_hygiene_anodevice_timer/Run()
	var/obj/item/anodevice/device = allocate(/obj/item/anodevice, run_loc_floor_bottom_left)
	device.duration = 1
	device.set_activated(TRUE)
	device.arm_emission_timer()
	TEST_ASSERT(after_pending(device, "emission"), "arm_emission_timer() did not schedule the end of the run")
	for(var/i in 1 to 40)
		if(!device.activated)
			break
		sleep(world.tick_lag)
	TEST_ASSERT(!device.activated, "the emission did not end when its timer came due")
	TEST_ASSERT(!after_pending(device, "emission"), "the fired timer id was not cleared")

	// Shutting down early cancels the timer.
	device.duration = 100
	device.set_activated(TRUE)
	device.arm_emission_timer()
	device.shutdown_emission()
	TEST_ASSERT(!after_pending(device, "emission"), "shutdown_emission() left the timer armed")
