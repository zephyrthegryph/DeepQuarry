/// Real timer transport nulls a deleted independent target; callback must finish without a kernel fault.
/datum/unit_test/c4_scanner_deleted_target

/datum/unit_test/c4_scanner_deleted_target/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	set_global("dview_mob", GLOB.dview_mob)
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, test_floor())
	user.enable_godmode()
	var/obj/item/paper/target = allocate(/obj/item/paper, test_floor())
	var/faults = length(kernel().fault_log)
	after(user, 1.5 SECONDS, GLOBAL_PROC_REF(detective_scanner_blood_report), key = "c4_scanner", with = list(user, target))
	TEST_ASSERT(after_pending(user, "c4_scanner"), "the actual delayed scanner report is queued")
	qdel(target)
	test_time(1.5 SECONDS)
	TEST_ASSERT(!after_pending(user, "c4_scanner"), "the actual report timer has fired")
	TEST_ASSERT_EQUAL(length(kernel().fault_log), faults, "the actual nulled report target produces no kernel fault")
	TEST_ASSERT(!QDELETED(user), "the surviving timer owner remains alive")

/datum/unit_test/c4_shelter_deleted_preview_user

/datum/unit_test/c4_shelter_deleted_preview_user/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	set_global("dview_mob", GLOB.dview_mob)
	var/obj/item/survivalcapsule/capsule = allocate(/obj/item/survivalcapsule, test_floor())
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, test_floor())
	var/faults = length(kernel().fault_log)
	after(capsule, 0.1 SECONDS, TYPE_PROC_REF(/obj/item/survivalcapsule, delete_preview_render), key = "c4_preview", with = list(user, list()))
	TEST_ASSERT(after_pending(capsule, "c4_preview"), "the real preview cleanup is queued on its independent capsule owner")
	qdel(user)
	test_time(0.1 SECONDS)
	TEST_ASSERT(!after_pending(capsule, "c4_preview"), "the actual cleanup timer fired")
	TEST_ASSERT_EQUAL(length(kernel().fault_log), faults, "the deleted preview user produces no cleanup fault")
	TEST_ASSERT(!QDELETED(capsule), "the surviving cleanup owner remains alive")

/// The extraction owner must complete disposal even after its payload vanishes.
/datum/unit_test/c4_fulton_deleted_payload

/datum/unit_test/c4_fulton_deleted_payload/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	set_global("dview_mob", GLOB.dview_mob)
	var/obj/effect/extraction_holder/holder = allocate(/obj/effect/extraction_holder, test_floor())
	var/obj/item/paper/payload = allocate(/obj/item/paper, holder)
	var/faults = length(kernel().fault_log)
	holder.fulton_expand(payload, test_floor())
	TEST_ASSERT(!QDELETED(holder), "the extraction starts with a live holder")
	qdel(payload)
	for(var/i in 1 to 180)
		test_time(0.1 SECONDS)
	TEST_ASSERT(QDELETED(holder), "the real extraction chain disposes its holder after losing the payload")
	TEST_ASSERT_EQUAL(length(kernel().fault_log), faults, "no stage faults after the independent payload is deleted")

/// Isolated production burn callback through the real timer's deleted-argument transport.
/datum/unit_test/c4_paper_burn_deleted_argument_timer_boundary
	var/bundle = FALSE
	var/delete_flame = FALSE

/datum/unit_test/c4_paper_burn_deleted_argument_timer_boundary/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	set_global("dview_mob", GLOB.dview_mob)
	var/turf/surface = test_floor()
	TEST_ASSERT(surface, "Actual map supplies a floor for paper burn callback isolation")
	var/obj/item/paper_owner
	if(bundle)
		paper_owner = allocate(/obj/item/paper_bundle, surface)
	else
		paper_owner = allocate(/obj/item/paper, surface)
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, surface)
	var/obj/item/flame/candle/flame = allocate(/obj/item/flame/candle, surface)
	TEST_ASSERT(user.put_in_active_hand(flame), "Real inventory holds the actual candle without lighting or gate writes")
	var/handler = bundle ? TYPE_PROC_REF(/obj/item/paper_bundle, burn_through) : TYPE_PROC_REF(/obj/item/paper, burn_through)
	var/faults = length(kernel().fault_log)
	after(paper_owner, 2 SECONDS, handler, key = "c4_paper_burn", with = list(user, flame, "notice"))
	TEST_ASSERT(after_pending(paper_owner, "c4_paper_burn"), "The independent paper owner has a real queued burn callback")
	if(delete_flame)
		qdel(flame)
	else
		qdel(user)
	test_time(2 SECONDS)
	TEST_ASSERT(!after_pending(paper_owner, "c4_paper_burn"), "The real production callback timer fires after argument deletion")
	TEST_ASSERT_EQUAL(length(kernel().fault_log), faults, "Missing user or flame produces no kernel callback fault")
	TEST_ASSERT(!QDELETED(paper_owner), "Missing burn arguments leave the actual paper or bundle intact")

/datum/unit_test/c4_paper_burn_deleted_argument_timer_boundary/flame
	delete_flame = TRUE

/datum/unit_test/c4_paper_burn_deleted_argument_timer_boundary/bundle
	bundle = TRUE

/datum/unit_test/c4_paper_burn_deleted_argument_timer_boundary/bundle/flame
	delete_flame = TRUE

// Isolated actual after() boundary proofs, not stochastic public gameplay entry coverage.
/datum/unit_test/retire_after_independent_handler_argument
	abstract_type = /datum/unit_test/retire_after_independent_handler_argument

/datum/unit_test/retire_after_independent_handler_argument/proc/exercise_timer(datum/owner, handler, datum/payload)
	var/faults_before = GLOB.total_runtimes
	TEST_ASSERT(after(owner, 0.1 SECONDS, handler, key = "retire_argument_probe", with = list(payload)), "Actual timer must accept the real owner and independent argument")
	TEST_ASSERT(after_pending(owner, "retire_argument_probe"), "Actual timer must be pending before argument deletion")
	qdel(payload)
	test_time(0.2 SECONDS)
	TEST_ASSERT(!QDELETED(owner), "Missing argument must not delete its independent owner")
	TEST_ASSERT(!after_pending(owner, "retire_argument_probe"), "Actual callback must retire the scheduled timer")
	TEST_ASSERT_EQUAL(GLOB.total_runtimes, faults_before, "Missing independent argument must not fault in the actual handler")

/datum/unit_test/retire_after_independent_handler_argument/dust

/datum/unit_test/retire_after_independent_handler_argument/dust/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	set_global("dview_mob", GLOB.dview_mob)
	var/turf/T = test_floor()
	var/obj/effect/anomaly/dust/dust = allocate(/obj/effect/anomaly/dust, T)
	var/mob/living/carbon/human/victim = allocate(/mob/living/carbon/human, T)
	exercise_timer(dust, TYPE_PROC_REF(/obj/effect/anomaly/dust, extraCough), victim)

/datum/unit_test/retire_after_independent_handler_argument/garbo

/datum/unit_test/retire_after_independent_handler_argument/garbo/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	set_global("dview_mob", GLOB.dview_mob)
	var/turf/T = test_floor()
	var/obj/machinery/v_garbosystem/grinder = allocate(/obj/machinery/v_garbosystem, T)
	var/obj/item/item = allocate(/obj/item, T)
	var/initial_operating = grinder.operating
	exercise_timer(grinder, TYPE_PROC_REF(/obj/machinery/v_garbosystem, crunch_item), item)
	TEST_ASSERT_EQUAL(grinder.operating, initial_operating, "Missing item does not alter the grinder's owner state")

/datum/unit_test/retire_after_independent_handler_argument/batterer

/datum/unit_test/retire_after_independent_handler_argument/batterer/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	set_global("dview_mob", GLOB.dview_mob)
	var/turf/T = test_floor()
	var/obj/item/batterer/c4_seeded/batterer = allocate(/obj/item/batterer/c4_seeded, T)
	var/mob/living/carbon/human/victim = allocate(/mob/living/carbon/human, T)
	exercise_timer(batterer, TYPE_PROC_REF(/obj/item/batterer/c4_seeded, seeded_effect), victim)
	TEST_ASSERT(batterer.probe_seed, "The timer exercised a seed whose first probability draw takes the damaging branch")

/datum/unit_test/retire_after_independent_handler_argument/autopsy

/datum/unit_test/retire_after_independent_handler_argument/autopsy/Run()
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	set_global("dview_mob", GLOB.dview_mob)
	var/turf/T = test_floor()
	var/obj/item/autopsy_scanner/scanner = allocate(/obj/item/autopsy_scanner, T)
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	exercise_timer(scanner, TYPE_PROC_REF(/obj/item/autopsy_scanner, print_report), user)

/// The isolated seam seeds immediately before the actual effect, so kernel work cannot consume its first draw.
/obj/item/batterer/c4_seeded
	var/probe_seed

/obj/item/batterer/c4_seeded/proc/seeded_effect(mob/living/carbon/human/M)
	for(var/candidate in 1 to 100)
		rand_seed(candidate)
		if(prob(50))
			probe_seed = candidate
			break
	rand_seed(probe_seed)
	mind_batter_effect(M)
