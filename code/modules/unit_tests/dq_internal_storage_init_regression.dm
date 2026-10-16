// The typed owner must not bind until native admission accepts the actual location.
/datum/unit_test/dq_internal_storage_init_regression

/datum/unit_test/dq_internal_storage_init_regression/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.act_taken), GLOB.act_taken)
	var/turf/T = run_loc_floor_bottom_left
	var/obj/item/owner = allocate(/obj/item, T)
	var/obj/item/storage/internal/S = allocate(/obj/item/storage/internal, owner)
	TEST_ASSERT(!QDELETED(S), "an actual item owner keeps its internal storage")
	TEST_ASSERT_EQUAL(S.master_item(), owner, "native setup binds the exact typed owner")
	TEST_ASSERT_EQUAL(S.name, owner.name, "native setup inherits the actual owner name")
	var/obj/item/storage/internal/invalid = allocate(/obj/item/storage/internal, T)
	TEST_ASSERT(QDELETED(invalid), "a turf-owned internal storage is rejected before an invalid typed link")
	var/obj/item/storage/internal/unowned = allocate(/obj/item/storage/internal, null)
	TEST_ASSERT(QDELETED(unowned), "null ownership is rejected by the same actual admission path")
	qdel(owner)
	TEST_ASSERT(QDELETED(S), "deleting the owner deletes its real contained storage")
