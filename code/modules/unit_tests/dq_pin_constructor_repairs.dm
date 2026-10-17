// Typed-reference declarations must preserve the constructors' absence cases.
/datum/unit_test/dq_pin_constructor_repairs
	abstract_type = /datum/unit_test/dq_pin_constructor_repairs

/datum/unit_test/dq_pin_constructor_repairs/New()
	..()
	dview(0, test_floor())
	status_policies()

/datum/unit_test/dq_pin_constructor_repairs/proc/scope_fixture()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.act_taken), GLOB.act_taken)

/datum/unit_test/dq_pin_constructor_repairs/internal_storage
/datum/unit_test/dq_pin_constructor_repairs/internal_storage/Run()
	scope_fixture()
	var/turf/T = test_floor()
	var/obj/item/storage/internal/invalid = allocate(/obj/item/storage/internal, T)
	TEST_ASSERT(QDELETED(invalid), "a floor spawn is rejected without a typed-reference runtime")
	var/obj/item/owner = allocate(/obj/item/pen, T)
	var/obj/item/storage/internal/valid = allocate(/obj/item/storage/internal, owner)
	TEST_ASSERT(!QDELETED(valid), "an actual item owner is accepted")
	TEST_ASSERT_EQUAL(valid.loc, owner, "the internal storage stays inside its owner")
	TEST_ASSERT_EQUAL(valid.master_item(), owner, "the native setup links the exact supplied item")
	TEST_ASSERT_EQUAL(valid.name, owner.name, "construction copies the owner's name before returning")
	var/obj/item/storage/internal/gripper/pocket = allocate(/obj/item/storage/internal/gripper, owner)
	TEST_ASSERT_EQUAL(pocket.master_item(), owner, "the real gripper-pocket subtype inherits the same link")
	TEST_ASSERT_EQUAL(pocket.name, owner.name, "the gripper pocket is named before its creator resumes")
	qdel(valid)
	TEST_ASSERT(!QDELETED(owner), "the reference does not make its item owner an owned child")

/datum/unit_test/dq_pin_constructor_repairs/cloning_scanner
/datum/unit_test/dq_pin_constructor_repairs/cloning_scanner/Run()
	scope_fixture()
	var/turf/T = test_floor()
	var/obj/machinery/computer/cloning/C = allocate(/obj/machinery/computer/cloning, T)
	TEST_ASSERT(!QDELETED(C), "a console without a scanner survives its real constructor")
	TEST_ASSERT_NULL(C.findscanner(), "an absent scanner is null rather than numeric zero")
	TEST_ASSERT_NULL(C.scanner(), "the typed reference is empty without a scanner")
	var/obj/machinery/dna_scannernew/S = allocate(/obj/machinery/dna_scannernew, get_step(T, EAST))
	C.updatemodules()
	TEST_ASSERT_EQUAL(C.findscanner(), S, "the real lookup finds an adjacent scanner")
	TEST_ASSERT_EQUAL(C.scanner(), S, "module refresh links that exact scanner")
	qdel(S)
	C.updatemodules()
	TEST_ASSERT_NULL(C.scanner(), "refresh after scanner deletion preserves a valid empty relation")

// Drive the actual pilot callback through the native timer, with a real helm
// whose nullspace location is deliberately included in the configured levels.
/datum/unit_test/dq_pin_constructor_repairs/pilotslug_helm_destination

/datum/unit_test/dq_pin_constructor_repairs/pilotslug_helm_destination/Run()
	scope_fixture()
	test_driver_begin()
	var/turf/start = test_floor()
	var/turf/destination = get_step(start, EAST)
	TEST_ASSERT(istype(destination), "Real neighboring turf exists")
	// Scope the map setting through the normal test override helper; no live
	// gameplay requirement depends on this static map configuration.
	set_var(using_map, nameof(using_map.player_levels), list(0))
	var/obj/machinery/computer/ship/helm/invalid = allocate(/obj/machinery/computer/ship/helm, start)
	invalid.moveToNullspace()
	TEST_ASSERT_NULL(get_turf(invalid), "The actual invalid candidate has no destination turf")
	TEST_ASSERT(invalid.z in using_map.player_levels, "The old z-only predicate would include this actual helm")
	var/mob/living/simple_mob/vore/alienanimals/catslug/custom/pilotslug/P = allocate(/mob/living/simple_mob/vore/alienanimals/catslug/custom/pilotslug, start)
	P.set_takes_a_helm(TRUE)
	P.set_ghostjoin(FALSE)
	after(P, 0, TYPE_PROC_REF(/mob/living/simple_mob/vore/alienanimals/catslug/custom/pilotslug, take_a_helm), key = "helm-destination-regression")
	TEST_ASSERT(after_pending(P, "helm-destination-regression"), "The real timer was queued before the clock advances")
	test_time(0.1 SECONDS)
	TEST_ASSERT(!after_pending(P, "helm-destination-regression"), "The real queued callback was delivered by the advanced clock")
	TEST_ASSERT_EQUAL(P.loc, start, "No valid destination leaves the real pilot in place")
	TEST_ASSERT(!P.ghostjoin, "Failed relocation does not open the pilot to ghosts")
	var/obj/machinery/computer/ship/helm/valid = allocate(/obj/machinery/computer/ship/helm, destination)
	TEST_ASSERT_EQUAL(get_turf(valid), destination, "The actual eligible helm has a real turf")
	using_map.player_levels += start.z
	var/list/eligible_helms = list()
	for(var/obj/machinery/computer/ship/helm/H in world)
		if(QDELETED(H))
			continue
		var/turf/helm_turf = get_turf(H)
		if(helm_turf && (helm_turf.z in using_map.player_levels))
			eligible_helms += H
	TEST_ASSERT_EQUAL(length(eligible_helms), 1, "The strict fixture has exactly one eligible real helm")
	TEST_ASSERT_EQUAL(eligible_helms[1], valid, "The only eligible real helm is the positive fixture target")
	after(P, 0, TYPE_PROC_REF(/mob/living/simple_mob/vore/alienanimals/catslug/custom/pilotslug, take_a_helm), key = "helm-destination-regression")
	TEST_ASSERT(after_pending(P, "helm-destination-regression"), "The real timer was queued before the clock advances")
	test_time(0.1 SECONDS)
	TEST_ASSERT(!after_pending(P, "helm-destination-regression"), "The real queued callback was delivered by the advanced clock")
	TEST_ASSERT_EQUAL(P.loc, destination, "The native timer relocates the pilot to the real valid helm")
	TEST_ASSERT(P.ghostjoin, "Successful actual relocation keeps the original ghost-admission behavior")
	test_driver_end()
