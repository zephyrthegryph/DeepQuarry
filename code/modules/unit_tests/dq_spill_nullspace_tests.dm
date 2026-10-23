// A machine or pipe destroyed in nullspace still puts its occupant out: the occupant goes to nullspace (as the old on_destroy did) instead
// of being deleted with the holder, which could delete a player's mob.

/datum/unit_test/dq_machine_spill_nullspace

/datum/unit_test/dq_machine_spill_nullspace/Run()
	var/turf/T = dq_containment_floor()
	var/obj/machinery/dna_scannernew/scanner = allocate(/obj/machinery/dna_scannernew, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	H.forceMove(scanner)
	TEST_ASSERT_EQUAL(H.loc, scanner, "the human is inside the scanner")
	scanner.moveToNullspace()
	TEST_ASSERT_NULL(scanner.loc, "the scanner is in nullspace")
	qdel(scanner)
	TEST_ASSERT(QDELETED(scanner), "the scanner is destroyed")
	TEST_ASSERT(!QDELETED(H), "the human survives the destruction of a machine in nullspace")
	TEST_ASSERT(H.loc != scanner, "the human is not left inside the destroyed machine")
	TEST_ASSERT_NULL(H.loc, "the human was moved out to nullspace, as before")

/datum/unit_test/dq_atmos_spill_nullspace

/datum/unit_test/dq_atmos_spill_nullspace/Run()
	var/turf/T = dq_containment_floor()
	var/obj/machinery/atmospherics/pipe/simple/hidden/supply/pipe = allocate(/obj/machinery/atmospherics/pipe/simple/hidden/supply, T)
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse, T)
	M.forceMove(pipe)
	TEST_ASSERT_EQUAL(M.loc, pipe, "the mouse is inside the pipe")
	pipe.moveToNullspace()
	TEST_ASSERT_NULL(pipe.loc, "the pipe is in nullspace")
	qdel(pipe)
	TEST_ASSERT(QDELETED(pipe), "the pipe is destroyed")
	TEST_ASSERT(!QDELETED(M), "the ventcrawler survives the destruction of a pipe in nullspace")
	TEST_ASSERT(M.loc != pipe, "the ventcrawler is not left inside the destroyed pipe")
	TEST_ASSERT_NULL(M.loc, "the ventcrawler was moved out to nullspace, as before")

/datum/unit_test/dq_atmos_spill_turf

/datum/unit_test/dq_atmos_spill_turf/Run()
	var/turf/T = dq_containment_floor()
	var/obj/machinery/atmospherics/pipe/simple/hidden/supply/pipe = allocate(/obj/machinery/atmospherics/pipe/simple/hidden/supply, T)
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse, T)
	M.forceMove(pipe)
	qdel(pipe)
	TEST_ASSERT(!QDELETED(M), "the ventcrawler survives a pipe destroyed on a turf")
	TEST_ASSERT_EQUAL(M.loc, T, "and is put out on the pipe's turf")
