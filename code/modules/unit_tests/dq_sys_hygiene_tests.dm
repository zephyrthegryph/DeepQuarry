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

/// Native URL messages reuse a scalar memo until a real item input changes.
/datum/unit_test/dq_sys_hygiene_asset_declared_cache
	parent_type = /datum/unit_test/dq_asset_memo

/datum/unit_test/dq_sys_hygiene_asset_declared_cache/Run()
	var/datum/asset/simple/dq_native_memo/A = prepare_fixture()
	var/datum/asset_transport/T = allocate(/datum/asset_transport)
	SSassets.set_transport(T)
	var/datum/asset_cache_item/I = allocate(/datum/asset_cache_item, "dq-hygiene-memo.css", icon('icons/effects/effects.dmi'), "hygiene-memo-hash")
	A.assets = list("dq-hygiene-memo.css" = I)
	var/message = A.get_serialized_url_mappings()
	TEST_ASSERT_NOTNULL(message, "Native serialized mappings were built")
	var/datum/memo_cell/cell = memo_cell_of(A, ASSET_URL_MESSAGE)
	var/computations = cell.computations
	TEST_ASSERT_EQUAL(A.get_serialized_url_mappings(), message, "Unchanged real inputs preserve the scalar output")
	TEST_ASSERT_EQUAL(cell.computations, computations, "An unchanged message is reused without recomputation")
	I.set_keep_local_name(TRUE)
	TEST_ASSERT_NOTEQUAL(A.get_serialized_url_mappings(), message, "Changing a real URL flag refreshes the message")
	TEST_ASSERT_EQUAL(cell.computations, computations + 1, "The changed projection is recomputed once, lazily")

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
