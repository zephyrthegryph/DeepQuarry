// Deleting a stocked circuit kit (code/modules/integrated_electronics/core/tools.dm) must not
// recurse: the kit, its circuit boxes and every circuit they hold all end in one transaction.
// The boxes build their ledgers lazily in their destroy transaction; sync() used to propagate per
// adopted circuit, re-entering itself once per circuit (ledger.dm, sync()).

/datum/unit_test/dq_circuit_kit_delete

/datum/unit_test/dq_circuit_kit_delete/Run()
	for(var/kit_type in list(/obj/item/storage/bag/circuits/all, /obj/item/storage/bag/circuits/basic))
		// A forced delete (cleanup, admin delete) takes every box and circuit with it in one transaction.
		var/obj/item/storage/bag/circuits/kit = new kit_type(run_loc_floor_bottom_left)
		var/list/inside = list()
		for(var/atom/movable/thing as anything in kit.GetAllContents())
			if(thing != kit)
				inside += thing
		var/circuits = 0
		for(var/obj/item/integrated_circuit/IC in inside)
			circuits++
		TEST_ASSERT(circuits > 0, "[kit_type] stocks circuits")
		var/before = GLOB.total_runtimes
		qdel(kit, force = TRUE)
		TEST_ASSERT_EQUAL(GLOB.total_runtimes - before, 0, "force-deleting [kit_type] logged no runtime")
		TEST_ASSERT(QDELETED(kit), "[kit_type] is deleted")
		for(var/atom/movable/thing as anything in inside)
			TEST_ASSERT(QDELETED(thing), "[thing] ([thing.type]) inside [kit_type] was deleted with it")

		// A gameplay delete spills the kit's contents instead (admission.md D10), again without a runtime.
		var/obj/item/storage/bag/circuits/spilled = new kit_type(run_loc_floor_bottom_left)
		var/list/held = list()
		for(var/obj/item/thing in spilled.contents)
			held += thing
		TEST_ASSERT(length(held), "[kit_type] holds boxes or circuits")
		before = GLOB.total_runtimes
		qdel(spilled)
		TEST_ASSERT_EQUAL(GLOB.total_runtimes - before, 0, "deleting [kit_type] logged no runtime")
		TEST_ASSERT(QDELETED(spilled), "[kit_type] is deleted")
		for(var/obj/item/thing as anything in held)
			TEST_ASSERT(!QDELETED(thing), "[thing] ([thing.type]) spilled from [kit_type] instead of being deleted")
			qdel(thing, force = TRUE)
