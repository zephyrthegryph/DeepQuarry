// Stored references (doc/rewrite/proposals/reference_storage.md): fixes found while converting the lists.

/// The medical console lists the records of GLOB.virusDB (virus id -> record); it once walked the keys as records and listed nothing.
/datum/unit_test/dq_refs_medical_lists_virus_records

/datum/unit_test/dq_refs_medical_lists_virus_records/Run()
	var/list/saved = GLOB.virusDB
	GLOB.virusDB = list()
	var/datum/data/record/rec = new
	rec.fields["name"] = "Test Plague"
	GLOB.virusDB["77"] = rec
	var/list/entries = medical_virus_entries()
	TEST_ASSERT_EQUAL(length(entries), 1, "the console lists the one discovered virus")
	TEST_ASSERT_EQUAL(entries[1]["name"], "Test Plague", "the entry carries the record's name")
	GLOB.virusDB = saved

/// The admin fax cache keeps the newest ADMIN_FAX_KEEP copies and deletes the older ones.
/datum/unit_test/dq_refs_admin_fax_cache_is_bounded

/datum/unit_test/dq_refs_admin_fax_cache_is_bounded/Run()
	test_driver_begin()
	var/list/saved = GLOB.adminfaxes
	GLOB.adminfaxes = list()
	var/obj/item/pen/first = new(null)
	admin_fax_keep(first)
	for(var/i in 1 to ADMIN_FAX_KEEP)
		admin_fax_keep(new /obj/item/pen(null))
	TEST_ASSERT_EQUAL(length(GLOB.adminfaxes), ADMIN_FAX_KEEP, "the cache holds no more than its limit")
	test_time(1 SECOND)
	TEST_ASSERT(QDELETED(first), "the oldest copy was deleted when it fell out of the cache")
	QDEL_LIST(GLOB.adminfaxes)
	GLOB.adminfaxes = saved

/// A deleted fake sun leaves the family registry (it was a static list nothing removed from).
/datum/unit_test/dq_refs_fake_sun_leaves_registry

/datum/unit_test/dq_refs_fake_sun_leaves_registry/Run()
	var/obj/effect/fake_sun/sun = allocate(/obj/effect/fake_sun, run_loc_floor_bottom_left)
	TEST_ASSERT(sun in REGISTRY_MEMBERS(REGISTRY_FAKE_SUNS), "a fake sun joins the registry")
	qdel(sun)
	TEST_ASSERT(!(sun in REGISTRY_MEMBERS(REGISTRY_FAKE_SUNS)), "a deleted fake sun leaves the registry")

/// A player's preferences refuse an unforced delete (they persist for the round) and a forced one removes them.
/datum/unit_test/dq_refs_preferences_refuse_unforced_delete

/datum/unit_test/dq_refs_preferences_refuse_unforced_delete/Run()
	var/datum/preferences/dq_preview_test_stub/prefs = new()
	qdel(prefs)
	TEST_ASSERT(!QDELETED(prefs), "an unforced delete leaves the preferences whole")
	qdel(prefs, TRUE)
	TEST_ASSERT(QDELETED(prefs), "a forced delete removes them")
