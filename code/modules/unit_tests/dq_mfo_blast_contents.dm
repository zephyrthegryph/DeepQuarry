// Behaviour pins for rewrite/missing-forms: how hard an explosion reaches what a holder carries. A probe inside each holder takes the blast the
// explosion service hands the holder's contents (dq_explosion_batch's blast(): the batch an explosion epoch delivers). Written against the
// explosion_contents_severity() overrides and pinned green on them before the declared entry replaced them.

/datum/unit_test/dq_explosion_batch/mfo_contents_share

/datum/unit_test/dq_explosion_batch/mfo_contents_share/Run()
	var/turf/T = test_floor()
	// holder type = the probe's integrity fraction left after a severity 2 blast on the holder (0.5: the full blast reached it; 0.75: one step
	// down, severity 3; 1: shielded)
	var/list/cases = list(
		/obj/machinery/bodyscanner = 0.5,
		/obj/machinery/clonepod = 0.5,
		/obj/machinery/dna_scannernew = 0.5,
		/obj/structure/morgue = 0.5,
		/obj/structure/bookcase = 0.5,
		/obj/item/paicard = 0.5,
		/obj/structure/transit_tube_pod = 0.5,
		/obj/machinery/atmospherics/pipe/simple/visible = 0.5,
		/obj/structure/closet = 0.75,
		/obj/structure/bed = 1,
	)
	for(var/holder_type in cases)
		var/atom/movable/holder = allocate(holder_type, T)
		var/obj/structure/closet/C = holder
		if(istype(C))
			C.opened = FALSE
		var/obj/structure/dq_blast_probe/inner = allocate(/obj/structure/dq_blast_probe, T)
		inner.forceMove(holder)
		blast(list(holder), 2)
		var/expected = cases[holder_type] * inner.max_integrity
		TEST_ASSERT_EQUAL(inner.get_integrity(), expected, "[holder_type]: its contents took [inner.get_integrity()] of [inner.max_integrity], expected [expected]")
		qdel(inner)
		if(!QDELETED(holder))
			qdel(holder)

/// A closet shields a light blast entirely.
/datum/unit_test/dq_explosion_batch/mfo_closet_shields_a_light_blast

/datum/unit_test/dq_explosion_batch/mfo_closet_shields_a_light_blast/Run()
	var/turf/T = test_floor()
	var/obj/structure/closet/C = allocate(/obj/structure/closet, T)
	C.opened = FALSE
	var/obj/structure/dq_blast_probe/inner = allocate(/obj/structure/dq_blast_probe, T)
	inner.forceMove(C)
	blast(list(C), 3)
	TEST_ASSERT_EQUAL(inner.get_integrity(), inner.max_integrity, "a light blast on a closet leaves what it holds untouched")
