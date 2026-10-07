/// Real timer transport nulls a deleted independent target; callback must finish without a kernel fault.
/datum/unit_test/c4_scanner_deleted_target

/datum/unit_test/c4_scanner_deleted_target/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
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
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
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
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
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
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
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
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
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
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	set_global("dview_mob", GLOB.dview_mob)
	var/turf/T = test_floor()
	var/obj/effect/anomaly/dust/dust = allocate(/obj/effect/anomaly/dust, T)
	var/mob/living/carbon/human/victim = allocate(/mob/living/carbon/human, T)
	exercise_timer(dust, TYPE_PROC_REF(/obj/effect/anomaly/dust, extraCough), victim)

/datum/unit_test/retire_after_independent_handler_argument/garbo

/datum/unit_test/retire_after_independent_handler_argument/garbo/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
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
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
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
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
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

/// Real public toy battle; deleting the other toy must release the survivor.
/datum/unit_test/c4_brawl_deleted_attacker
	var/delete_before_exchange = FALSE

/datum/unit_test/c4_brawl_deleted_attacker/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	test_driver_begin()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	set_global("dview_mob", GLOB.dview_mob)
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/turf/surface = test_floor()
	var/mob/living/carbon/human/controller = allocate(/mob/living/carbon/human, surface)
	var/obj/item/toy/mecha/ripley/attacker = allocate(/obj/item/toy/mecha/ripley, surface)
	var/obj/item/toy/mecha/ripley/defender = allocate(/obj/item/toy/mecha/ripley, surface)
	TEST_ASSERT(controller.put_in_active_hand(attacker), "Actual inventory holds the attacking toy")
	TEST_ASSERT(defender.combat_can_continue(attacker, controller, null), "The actual controller can operate both real nearby toys")
	defender.mecha_brawl(attacker, controller, null)
	TEST_ASSERT(defender.in_combat && attacker.in_combat, "Public battle entry puts both actual toys in combat")
	if(delete_before_exchange)
		test_time(1 SECOND)
		TEST_ASSERT(defender.in_combat && attacker.in_combat, "Actual first round keeps the two healthy toys in combat until their exchange")
	var/faults = length(kernel().fault_log)
	qdel(attacker)
	test_time(delete_before_exchange ? 0.5 SECONDS : 1 SECOND)
	TEST_ASSERT_EQUAL(length(kernel().fault_log), faults, "The missing attacker does not fault the real battle callback")
	TEST_ASSERT(!QDELETED(defender) && !defender.in_combat, "The surviving toy leaves combat after its opponent disappears")
	TEST_ASSERT_EQUAL(defender.combat_health, defender.max_combat_health, "Cancellation restores the survivor's normal battle health")
	TEST_ASSERT_EQUAL(defender.wins, 0, "A deleted opponent does not invent a victory")
	TEST_ASSERT_EQUAL(defender.losses, 0, "A deleted opponent does not invent a defeat")

/datum/unit_test/c4_brawl_deleted_attacker/exchange
	delete_before_exchange = TRUE

/// Explicit timer-boundary isolation: mounted gun/user absence avoids consuming ammunition.
/datum/unit_test/c4_gun_storage_deleted_loader_timer_boundary

/datum/unit_test/c4_gun_storage_deleted_loader_timer_boundary/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	test_driver_begin()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	set_global("dview_mob", GLOB.dview_mob)
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/turf/surface = test_floor()
	var/obj/item/gun/projectile/revolver/gun = allocate(/obj/item/gun/projectile/revolver, surface)
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, surface)
	var/obj/item/ammo_casing/a357/round = allocate(/obj/item/ammo_casing/a357, surface)
	var/list/rounds = list(round)
	var/loaded_before = length(gun.loaded)
	var/faults = length(kernel().fault_log)
	after(gun, 1 SECOND, TYPE_PROC_REF(/obj/item/gun/projectile, load_from_storage), key = "c4_load", with = list(user, rounds))
	TEST_ASSERT(after_pending(gun, "c4_load"), "The actual gun owns a queued loader callback")
	qdel(user)
	test_time(1 SECOND)
	TEST_ASSERT(!after_pending(gun, "c4_load"), "The actual loader callback fires")
	TEST_ASSERT_EQUAL(length(kernel().fault_log), faults, "The deleted loader actor does not fault")
	TEST_ASSERT_EQUAL(length(gun.loaded), loaded_before, "A vanished actor transfers no ammunition")
	TEST_ASSERT_EQUAL(length(rounds), 1, "A vanished actor does not consume the pending round list")
	TEST_ASSERT(!QDELETED(round) && round.loc == surface, "The real pending round remains intact on its original floor")

// Real after() boundary proofs; no connected-client resurrection or backup creation claimed.
/datum/unit_test/retire_artifact_deleted_message_holder

/datum/unit_test/retire_artifact_deleted_message_holder/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	test_driver_begin()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	set_global("dview_mob", GLOB.dview_mob)
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/turf/T = test_floor()
	var/mob/living/carbon/human/body = allocate(/mob/living/carbon/human, T)
	var/obj/item/holder = allocate(/obj/item, T)
	TEST_ASSERT(!body.client, "Actual allocated body must exercise the no-returning-client branch")
	var/original_stat = body.stat
	var/faults_before = GLOB.total_runtimes
	TEST_ASSERT(after(body, 0.1 SECONDS, GLOBAL_PROC_REF(artifact_revive_wakes), key = "revive_holder_probe", with = list(body, holder)), "Actual timer captures an independent message holder")
	qdel(holder)
	test_time(0.2 SECONDS)
	TEST_ASSERT_EQUAL(GLOB.total_runtimes, faults_before, "Deleted message holder must not fault in the actual wake callback")
	TEST_ASSERT(!QDELETED(body), "Missing message holder must preserve timer-owner body")
	TEST_ASSERT_EQUAL(body.stat, original_stat, "No returning client means no status transition")
	TEST_ASSERT(!after_pending(body, "revive_holder_probe"), "Actual wake callback timer retires")

/datum/unit_test/retire_resleeve_deleted_backup_record

/datum/unit_test/retire_resleeve_deleted_backup_record/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	test_driver_begin()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	set_global("dview_mob", GLOB.dview_mob)
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/turf/T = test_floor()
	var/mob/living/carbon/human/body = allocate(/mob/living/carbon/human, T)
	var/datum/mind/mind = new("retire_backup_record")
	own(mind)
	var/datum/transhuman/mind_record/record = new(mind, body, FALSE)
	own(record)
	var/obj/item/nif/original_nif = body.nif
	var/faults_before = GLOB.total_runtimes
	TEST_ASSERT(after(body, 0.1 SECONDS, GLOBAL_PROC_REF(resleeve_restore_nif), key = "restore_record_probe", with = list(body, record)), "Actual timer captures its independent real backup record")
	qdel(record)
	test_time(0.2 SECONDS)
	TEST_ASSERT_EQUAL(GLOB.total_runtimes, faults_before, "Deleted backup record must not fault in the actual restoration callback")
	TEST_ASSERT(!QDELETED(body), "Missing backup data must preserve the actual body")
	TEST_ASSERT_EQUAL(body.nif, original_nif, "Absent backup data must not replace the body's current NIF")
	TEST_ASSERT(!after_pending(body, "restore_record_probe"), "Actual restoration callback timer retires")

/datum/unit_test/retire_after_independent_handler_argument/bookbinder

/datum/unit_test/retire_after_independent_handler_argument/bookbinder/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	test_driver_begin()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	set_global("dview_mob", GLOB.dview_mob)
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/turf/T = test_floor()
	var/obj/machinery/bookbinder/binder = allocate(/obj/machinery/bookbinder, T)
	var/obj/item/paper/paper = allocate(/obj/item/paper, binder)
	var/books_before = length(turf_contents_of_type(T, /obj/item/book))
	exercise_timer(binder, TYPE_PROC_REF(/obj/machinery/bookbinder, bind_paper), paper)
	TEST_ASSERT_EQUAL(length(turf_contents_of_type(T, /obj/item/book)), books_before, "A missing source must not create an empty book")
	var/obj/item/paper_bundle/bundle = allocate(/obj/item/paper_bundle, binder)
	exercise_timer(binder, TYPE_PROC_REF(/obj/machinery/bookbinder, bind_bundle), bundle)
	TEST_ASSERT_EQUAL(length(turf_contents_of_type(T, /obj/item/book)), books_before, "A missing bundle must not create an empty bound bundle")

/datum/unit_test/retire_after_independent_handler_argument/hyperpad

/datum/unit_test/retire_after_independent_handler_argument/hyperpad/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	test_driver_begin()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	set_global("dview_mob", GLOB.dview_mob)
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/turf/T = test_floor()
	var/obj/machinery/hyperpad/centre/centre = allocate(/obj/machinery/hyperpad/centre, T)
	var/obj/machinery/hyperpad/pad = allocate(/obj/machinery/hyperpad, T)
	exercise_timer(centre, TYPE_PROC_REF(/obj/machinery/hyperpad/centre, animate_discharge), pad)
	pad = allocate(/obj/machinery/hyperpad, T)
	var/faults = GLOB.total_runtimes
	var/mutable_appearance/color = mutable_appearance('icons/obj/telescience_ch.dmi', "hpad_on")
	after(centre, 0.1 SECONDS, TYPE_PROC_REF(/obj/machinery/hyperpad/centre, animate_charge), key = "retire_argument_probe", with = list(pad, color))
	qdel(pad)
	test_time(0.2 SECONDS)
	TEST_ASSERT(!after_pending(centre, "retire_argument_probe"), "Charge callback must fire despite missing independent pad")
	TEST_ASSERT_EQUAL(GLOB.total_runtimes, faults, "Missing pad must not fault either animation callback")

/// Isolated completion callback: deliberately seeded busy state tests the cleanup tail.
/datum/unit_test/retire_resleeve_deleted_injector_completion

/datum/unit_test/retire_resleeve_deleted_injector_completion/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	test_driver_begin()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	set_global("dview_mob", GLOB.dview_mob)
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/turf/T = test_floor()
	var/obj/machinery/computer/transhuman/resleeving/computer = allocate(/obj/machinery/computer/transhuman/resleeving, T)
	var/obj/item/dnainjector/injector = allocate(/obj/item/dnainjector, computer)
	computer.gene_sequencing = TRUE
	var/faults = GLOB.total_runtimes
	after(computer, 0.1 SECONDS, TYPE_PROC_REF(/obj/machinery/computer/transhuman/resleeving, dispense_injector), key = "retire_injector_probe", with = list(injector))
	qdel(injector)
	test_time(0.2 SECONDS)
	TEST_ASSERT(!after_pending(computer, "retire_injector_probe"), "Actual completion timer fires after injector deletion")
	TEST_ASSERT_EQUAL(GLOB.total_runtimes, faults, "Missing injector must not fault the completion callback")
	TEST_ASSERT(!computer.gene_sequencing, "Missing injector must still release the sequencing busy state")

/// Real station arrival/launch stages and a pod removed during delayed completion; launch availability is not exercised.
/datum/unit_test/c4_transit_deleted_pod
	var/arrival = TRUE

/datum/unit_test/c4_transit_deleted_pod/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	test_driver_begin()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	set_global("dview_mob", GLOB.dview_mob)
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/turf/surface = test_floor()
	TEST_ASSERT(surface, "Actual map supplies a transit test floor")
	var/obj/structure/transit_tube_pod/pod = allocate(/obj/structure/transit_tube_pod, surface)
	var/obj/structure/transit_tube/station/station = allocate(/obj/structure/transit_tube/station, surface)
	var/faults = length(kernel().fault_log)
	if(arrival)
		station.pod_stopped(pod, pod.dir)
	else
		station.launch_close(pod)
	TEST_ASSERT(station.pod_moving, "Public station entry establishes real movement in progress")
	qdel(pod)
	test_time(1.4 SECONDS)
	TEST_ASSERT_EQUAL(length(kernel().fault_log), faults, "Deleted pod causes no station completion fault")
	TEST_ASSERT(!QDELETED(station), "The actual station survives its vanished pod")
	TEST_ASSERT_EQUAL(station.pod_moving, 0, "Station completion releases actual movement state after pod deletion")
	if(arrival)
		TEST_ASSERT_EQUAL(station.icon_state, "open", "Existing arrival animation completes independently of the lost pod")

/datum/unit_test/c4_transit_deleted_pod/launch
	arrival = FALSE

/// Isolated real timer boundary: native argument capture clears removed vents before arrival.
/datum/unit_test/c4_solargrub_missing_vents
	var/remove_origin = FALSE
	var/remove_end = TRUE
	var/weld_end = FALSE

/datum/unit_test/c4_solargrub_missing_vents/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	test_driver_begin()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	set_global("dview_mob", GLOB.dview_mob)
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/turf/current = test_floor()
	var/turf/origin_floor = get_step(current, EAST)
	TEST_ASSERT(origin_floor, "The fixture has a distinct surviving origin floor")
	var/mob/living/simple_mob/animal/solargrub_larva/grub = allocate(/mob/living/simple_mob/animal/solargrub_larva, current)
	var/obj/machinery/atmospherics/unary/vent_pump/origin = allocate(/obj/machinery/atmospherics/unary/vent_pump, origin_floor)
	var/obj/machinery/atmospherics/unary/vent_pump/end = allocate(/obj/machinery/atmospherics/unary/vent_pump, current)
	if(weld_end)
		set_welded(end, TRUE)
		TEST_ASSERT(is_welded(end), "The real exit is welded before its origin disappears")
	var/faults = length(kernel().fault_log)
	after(grub, 0.1 SECONDS, TYPE_PROC_REF(/mob/living/simple_mob/animal/solargrub_larva, ventcrawl_arrive), key = "c4_grub_arrival", with = list(origin, end, 3))
	TEST_ASSERT(after_pending(grub, "c4_grub_arrival"), "The real arrival callback is pending with independent vents")
	if(remove_origin)
		qdel(origin)
	if(remove_end)
		qdel(end)
	test_time(0.1 SECONDS)
	TEST_ASSERT(!after_pending(grub, "c4_grub_arrival"), "The actual arrival timer fired")
	TEST_ASSERT(!QDELETED(grub), "The independent callback owner survives the missing vents")
	TEST_ASSERT_EQUAL(length(kernel().fault_log), faults, "The real arrival callback faults neither in is_welded nor network lookup")
	TEST_ASSERT_EQUAL(get_turf(grub), remove_origin ? current : origin_floor, "Missing exit returns to surviving origin, otherwise retains current floor")

/datum/unit_test/c4_solargrub_missing_vents/origin_missing_welded_exit
	remove_origin = TRUE
	remove_end = FALSE
	weld_end = TRUE

/datum/unit_test/c4_solargrub_missing_vents/both_missing
	remove_origin = TRUE
// Actual activation and public collision entry; the captured mineral is replaced through ChangeTurf.
/datum/unit_test/retire_gigadrill_replaced_mineral_timer

/datum/unit_test/retire_gigadrill_replaced_mineral_timer/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	test_driver_begin()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	set_global("dview_mob", GLOB.dview_mob)
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	var/turf/simulated/mineral/mineral
	var/turf/surface
	for(var/turf/simulated/mineral/candidate in world)
		if(contents_count(candidate))
			continue
		for(var/direction in GLOB.cardinal)
			var/turf/neighbor = get_step(candidate, direction)
			if(istype(neighbor, /turf/simulated/floor) && !neighbor.density && !contents_count(neighbor))
				mineral = candidate
				surface = neighbor
				break
		if(mineral)
			break
	TEST_ASSERT(mineral && surface, "Actual map must supply an unoccupied mineral with an adjacent open floor")
	defer_cleanup(src, PROC_REF(restore_mineral), mineral.x, mineral.y, mineral.z, mineral.type)
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, surface)
	var/obj/machinery/giga_drill/drill = allocate(/obj/machinery/giga_drill, surface)
	TEST_ASSERT(!drill.active && !drill.drilling_turf(), "Real drill must begin idle")
	var/datum/op_result/result = test_click(actor, drill)
	TEST_ASSERT(result && result.key == "toggle" && !(result.outcome & ACT_REFUSED) && drill.active, "Actual hand operation must activate the drill")
	drill.Bump(mineral)
	TEST_ASSERT(drill.anchored, "Public mineral collision must anchor the actual drill")
	TEST_ASSERT_EQUAL(drill.drilling_turf(), surface, "Public collision must record the drill's own turf")
	var/faults_before = GLOB.total_runtimes
	var/turf/replacement = mineral.ChangeTurf(/turf/simulated/floor)
	TEST_ASSERT(istype(replacement, /turf/simulated/floor), "Production ChangeTurf must replace the captured mineral")
	test_time(drill.drill_time + 0.1 SECONDS)
	TEST_ASSERT_EQUAL(GLOB.total_runtimes, faults_before, "Missing original mineral must not fault in the real completion callback")
	TEST_ASSERT(!drill.anchored, "Missing target must still release the owner anchor")
	TEST_ASSERT_NULL(drill.drilling_turf(), "Missing target must still clear the owner drilling relation")
	TEST_ASSERT_EQUAL(get_turf(drill), surface, "Missing target must not move the drill onto the replacement")

/datum/unit_test/retire_gigadrill_replaced_mineral_timer/proc/restore_mineral(x, y, z, original_type)
	var/turf/current = locate(x, y, z)
	if(current && current.type != original_type)
		current.ChangeTurf(original_type)

/// Isolated nullable-argument arrival boundary, not public attack or map-release coverage.
/datum/unit_test/c4_jaunt_missing_saved_turf
	var/mob_type = /mob/living/simple_mob/humanoid/cultist/human/bloodjaunt
	var/emerged_state = "bloodin"
	var/arrival_handler = TYPE_PROC_REF(/mob/living/simple_mob/humanoid/cultist/human/bloodjaunt, do_special_attack_1)

/datum/unit_test/c4_jaunt_missing_saved_turf/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	test_driver_begin()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	set_global("dview_mob", GLOB.dview_mob)
	var/turf/surface = test_floor()
	var/mob/living/simple_mob/actor = allocate(mob_type, surface)
	TEST_ASSERT(actor.ai_brain, "The real mob owns its actual AI brain")
	actor.ai_busy_begin()
	TEST_ASSERT(actor.ai_brain.is_busy(), "A real windup hold claims the AI before arrival")
	var/faults = length(kernel().fault_log)
	after(actor, 0.1 SECONDS, arrival_handler, key = "c4_jaunt", with = list(null, null, surface))
	TEST_ASSERT(after_pending(actor, "c4_jaunt"), "The actual arrival handler is pending with a missing saved destination")
	test_time(0.1 SECONDS)
	TEST_ASSERT(!after_pending(actor, "c4_jaunt"), "The real arrival timer fired")
	TEST_ASSERT(!actor.ai_brain.is_busy(), "The missing saved destination releases the actual busy hold")
	TEST_ASSERT_EQUAL(actor.icon_state, emerged_state, "The mob restores its actual emergence state")
	TEST_ASSERT_EQUAL(actor.loc, surface, "Aborted travel preserves the real mob's floor")
	TEST_ASSERT_EQUAL(length(kernel().fault_log), faults, "Missing saved destination never reaches get_dist/jaunt movement")

/datum/unit_test/c4_jaunt_missing_saved_turf/wraith
	mob_type = /mob/living/simple_mob/construct/wraith
	emerged_state = "phase_shift2"
	arrival_handler = TYPE_PROC_REF(/mob/living/simple_mob/construct/wraith, do_special_attack_1)

/datum/unit_test/c4_tunneler_missing_saved_turf

/datum/unit_test/c4_tunneler_missing_saved_turf/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	test_driver_begin()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	set_global("dview_mob", GLOB.dview_mob)
	var/turf/surface = test_floor()
	var/mob/living/simple_mob/animal/giant_spider/tunneler/spider = allocate(/mob/living/simple_mob/animal/giant_spider/tunneler, surface)
	TEST_ASSERT(spider.ai_brain, "The real tunneler owns its actual brain")
	spider.ai_busy_begin()
	TEST_ASSERT(spider.ai_brain.is_busy(), "The pending dig owns a real busy hold")
	var/faults = length(kernel().fault_log)
	after(spider, 0.1 SECONDS, TYPE_PROC_REF(/mob/living/simple_mob/animal/giant_spider/tunneler, tunnel_dig), key = "c4_dig", with = list(null, surface, null))
	TEST_ASSERT(after_pending(spider, "c4_dig"), "The actual dig callback is queued with missing origin")
	test_time(0.1 SECONDS)
	TEST_ASSERT(!after_pending(spider, "c4_dig"), "The actual dig timer fired")
	TEST_ASSERT(!spider.ai_brain.is_busy(), "The lost saved origin releases the busy hold before submerge")
	TEST_ASSERT_EQUAL(spider.alpha, initial(spider.alpha), "Aborted initial dig never submerges the surviving spider")
	TEST_ASSERT_EQUAL(spider.loc, surface, "The aborted dig preserves its actual origin")
	TEST_ASSERT_EQUAL(length(kernel().fault_log), faults, "Lost saved origin never reaches tunnel distance or direction")
/// Explicit production timer-boundary isolation, not full antagonist spawning.
/datum/unit_test/c4_antag_finish_deleted_mob_timer_boundary
	var/drone = FALSE

/datum/unit_test/c4_antag_finish_deleted_mob_timer_boundary/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	test_driver_begin()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	set_global("dview_mob", GLOB.dview_mob)
	var/turf/surface = test_floor()
	var/obj/item/antag_spawner/spawner
	var/mob/spawned
	var/handler
	if(drone)
		spawner = allocate(/obj/item/antag_spawner/syndicate_drone, surface)
		spawned = allocate(/mob/living/silicon/robot, surface)
		handler = TYPE_PROC_REF(/obj/item/antag_spawner/syndicate_drone, finish_drone_spawn)
	else
		spawner = allocate(/obj/item/antag_spawner/technomancer_apprentice, surface)
		spawned = allocate(/mob/living/carbon/human, surface)
		handler = TYPE_PROC_REF(/obj/item/antag_spawner/technomancer_apprentice, finish_technomancer_spawn)
	var/faults = length(kernel().fault_log)
	after(spawner, 0.1 SECONDS, handler, key = "c4_spawn_finish", with = list(spawned))
	TEST_ASSERT(after_pending(spawner, "c4_spawn_finish"), "Actual spawner queues its production finish callback")
	qdel(spawned)
	test_time(0.1 SECONDS)
	TEST_ASSERT_EQUAL(length(kernel().fault_log), faults, "Missing spawned mob causes no callback fault")
	TEST_ASSERT(QDELETED(spawner), "The real spawner still consumes its one-use item after the vanished spawn")

/datum/unit_test/c4_antag_finish_deleted_mob_timer_boundary/drone
	drone = TRUE

/datum/unit_test/c4_apportation_deleted_user_timer_boundary

/datum/unit_test/c4_apportation_deleted_user_timer_boundary/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	test_driver_begin()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	set_global("dview_mob", GLOB.dview_mob)
	var/turf/surface = test_floor()
	var/obj/item/spell/apportation/spell = allocate(/obj/item/spell/apportation, surface)
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, surface)
	var/mob/living/carbon/human/target = allocate(/mob/living/carbon/human, surface)
	var/faults = length(kernel().fault_log)
	after(spell, 1 SECOND, TYPE_PROC_REF(/obj/item/spell/apportation, finish_apportation_grab), key = "c4_apportation", with = list(user, target))
	TEST_ASSERT(after_pending(spell, "c4_apportation"), "Actual spell owns its delayed grab callback")
	qdel(user)
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(length(kernel().fault_log), faults, "Vanished caster does not fault the pending grab")
	TEST_ASSERT(QDELETED(spell), "The original canceled-grab consume tail still removes the spell")
	TEST_ASSERT_EQUAL(target.status_units(STAT_WEAKENED), 0, "The actual surviving target receives no grab weakness")

/datum/unit_test/c4_passwall_deleted_user_timer_boundary

/datum/unit_test/c4_passwall_deleted_user_timer_boundary/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	test_driver_begin()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	set_global("dview_mob", GLOB.dview_mob)
	var/turf/surface = test_floor()
	TEST_ASSERT(surface, "Actual map provides a nonnull found destination")
	var/obj/item/spell/passwall/spell = allocate(/obj/item/spell/passwall, surface)
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, surface)
	var/faults = length(kernel().fault_log)
	after(spell, 1 SECOND, TYPE_PROC_REF(/obj/item/spell/passwall, passwall_found), key = "c4_passwall", with = list(user, surface, surface, surface, 0))
	TEST_ASSERT(after_pending(spell, "c4_passwall"), "Actual spell owns a delayed completion with a real found turf")
	qdel(user)
	test_time(1 SECOND)
	TEST_ASSERT(!after_pending(spell, "c4_passwall"), "Actual completion fired instead of being silently skipped")
	TEST_ASSERT_EQUAL(length(kernel().fault_log), faults, "Nonnull found turf and deleted user cause no callback fault")
	TEST_ASSERT(!QDELETED(spell) && spell.loc == surface, "Missing caster preserves existing canceled passwall spell state")

/datum/unit_test/c4_vac_deleted_target_timer_boundary
	var/consuming = FALSE

/datum/unit_test/c4_vac_deleted_target_timer_boundary/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	test_driver_begin()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	set_global("dview_mob", GLOB.dview_mob)
	var/turf/surface = test_floor()
	var/obj/item/vac_attachment/vac = allocate(/obj/item/vac_attachment, surface)
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, surface)
	var/obj/item/target = allocate(/obj/item, surface)
	var/faults = length(kernel().fault_log)
	if(consuming)
		after(vac, 0.5 SECONDS, TYPE_PROC_REF(/obj/item/vac_attachment, handle_consumption), key = "c4_vac", with = list(target, user, 1, surface))
	else
		after(vac, 0.5 SECONDS, TYPE_PROC_REF(/obj/item/vac_attachment, prepare_sucking), key = "c4_vac", with = list(target, user, surface))
	TEST_ASSERT(after_pending(vac, "c4_vac"), "Real attachment owns its pending production callback")
	qdel(target)
	test_time(0.5 SECONDS)
	TEST_ASSERT(!after_pending(vac, "c4_vac"), "Actual vac callback fired")
	TEST_ASSERT_EQUAL(length(kernel().fault_log), faults, "Vanished target causes no vac callback fault")
	TEST_ASSERT(!QDELETED(vac) && vac.loc == surface && user.loc == surface, "Actual vac and actor survive cancellation in their original location")

/datum/unit_test/c4_vac_deleted_target_timer_boundary/consuming
	consuming = TRUE

/// Explicit missing-destination callback isolation; no map turf is deleted.
/datum/unit_test/c4_transportpod_missing_destination_timer_boundary

/datum/unit_test/c4_transportpod_missing_destination_timer_boundary/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	test_driver_begin()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	set_global("dview_mob", GLOB.dview_mob)
	var/turf/surface = test_floor()
	var/obj/machinery/transportpod/pod = allocate(/obj/machinery/transportpod, surface)
	var/faults = length(kernel().fault_log)
	after(pod, 1 SECOND, TYPE_PROC_REF(/obj/machinery/transportpod, arrive), key = "c4_arrive", with = list(null))
	TEST_ASSERT(after_pending(pod, "c4_arrive"), "Actual pod owns its completion timer with missing destination")
	test_time(1 SECOND)
	TEST_ASSERT(!after_pending(pod, "c4_arrive"), "Actual arrival callback fired")
	TEST_ASSERT_EQUAL(pod.loc, surface, "Missing destination preserves original landing turf instead of moving the pod into nullspace")
	test_time(0.5 SECONDS)
	TEST_ASSERT_EQUAL(length(kernel().fault_log), faults, "Missing destination preserves fault-free unload and ending")
	TEST_ASSERT(QDELETED(pod), "Existing unload and self-delete tail still completes")

/datum/unit_test/c4_toilet_deleted_flush_target_timer_boundary

/datum/unit_test/c4_toilet_deleted_flush_target_timer_boundary/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	test_driver_begin()
	set_global("act_taken", GLOB.act_taken)
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	set_global("dview_mob", GLOB.dview_mob)
	var/turf/surface = test_floor()
	var/obj/structure/toilet/toilet = allocate(/obj/structure/toilet, surface)
	var/obj/item/paper/target = allocate(/obj/item/paper, surface)
	var/faults = length(kernel().fault_log)
	after(toilet, 0.1 SECONDS, TYPE_PROC_REF(/obj/structure/toilet, tertiary_flush), key = "c4_flush", with = list(target, TRUE))
	TEST_ASSERT(after_pending(toilet, "c4_flush"), "Actual toilet owns its pending final target-transfer callback")
	qdel(target)
	test_time(0.1 SECONDS)
	TEST_ASSERT(!after_pending(toilet, "c4_flush"), "Actual flush completion callback fired")
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(length(kernel().fault_log), faults, "Missing flush target and the preserved send tail produce no fault")
	TEST_ASSERT(!QDELETED(toilet), "Actual toilet survives the deleted independent target")
	TEST_ASSERT_EQUAL(LAZYLEN(toilet.currently_held_objects), 0, "The deleted target is not retained in actual flushed contents")

/// Explicit production callback isolation with a real wearer/core/spell constructor.
/datum/unit_test/c4_delayed_spell_deleted_core_timer_boundary

/datum/unit_test/c4_delayed_spell_deleted_core_timer_boundary/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	test_driver_begin()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	set_global("dview_mob", GLOB.dview_mob)
	var/turf/surface = test_floor()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, surface)
	var/obj/item/technomancer_core/core = allocate(/obj/item/technomancer_core, surface)
	TEST_ASSERT(user.equip_to_slot_if_possible(core, SLOT_ID_BACK), "Actual wearer equips the real core through inventory")
	var/obj/item/spell/projectile/overload/spell = allocate(/obj/item/spell/projectile/overload, user)
	TEST_ASSERT(!QDELETED(spell) && spell.owner_ref() == user && spell.core == core, "Real spell constructor binds the original wearer and actual worn core")
	var/image/target_image = image(icon = 'icons/obj/spells.dmi', loc = surface, icon_state = "target")
	var/faults = length(kernel().fault_log)
	after(spell, 0.1 SECONDS, TYPE_PROC_REF(/obj/item/spell/projectile, delayed_shot), key = "c4_spell", with = list(surface, user, target_image))
	TEST_ASSERT(after_pending(spell, "c4_spell"), "Actual spell owns its production delayed shot")
	qdel(core)
	TEST_ASSERT(!QDELETED(spell) && spell.owner_ref() == user, "Core deletion preserves the live spell and wearer for callback execution")
	test_time(0.1 SECONDS)
	TEST_ASSERT(!after_pending(spell, "c4_spell"), "Actual delayed shot callback fired")
	TEST_ASSERT_EQUAL(length(kernel().fault_log), faults, "Missing original core does not fault the overload continuation")
	TEST_ASSERT(!spell.shot_ready, "Canceled delayed shot does not leave ready state enabled")

/datum/unit_test/c4_mecha_burst_missing_chassis_timer_boundary

/datum/unit_test/c4_mecha_burst_missing_chassis_timer_boundary/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	test_driver_begin()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	set_global("dview_mob", GLOB.dview_mob)
	var/turf/surface = test_floor()
	var/obj/item/mecha_parts/mecha_equipment/weapon/weapon = allocate(/obj/item/mecha_parts/mecha_equipment/weapon, surface)
	var/obj/item/projectile/bullet/pistol/shot = allocate(/obj/item/projectile/bullet/pistol, surface)
	TEST_ASSERT(!weapon.chassis, "Actual unattached equipment constructor has no fake chassis relation")
	var/faults = length(kernel().fault_log)
	after(weapon, 0.1 SECONDS, TYPE_PROC_REF(/obj/item/mecha_parts/mecha_equipment/weapon, burst_fire), key = "c4_mech_burst", with = list(shot, surface, null))
	TEST_ASSERT(after_pending(weapon, "c4_mech_burst"), "Real equipment owns the pending shot callback")
	test_time(0.1 SECONDS)
	TEST_ASSERT(!after_pending(weapon, "c4_mech_burst"), "Real burst callback fired")
	TEST_ASSERT_EQUAL(length(kernel().fault_log), faults, "Missing chassis causes no delegated accuracy fault")
	TEST_ASSERT(QDELETED(shot), "Canceled burst releases its actual precreated projectile")
	TEST_ASSERT(!QDELETED(weapon), "Actual surviving equipment is not consumed with the shot")

/// Real callback transitions prepare an unsafe actor-dependent outcome without writing luck state.
/datum/unit_test/c4_capsule_deleted_owner_timer_boundary

/datum/unit_test/c4_capsule_deleted_owner_timer_boundary/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	test_driver_begin()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	set_global("dview_mob", GLOB.dview_mob)
	var/turf/surface = test_floor()
	var/obj/item/daredevice/device = allocate(/obj/item/daredevice, surface)
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, surface)
	var/list/actor_effects = list(1, 2, 3, 4, 5, 7, 9, 777)
	// Initial outcome0 and other unmatched outcomes only perform normal rerandomization/reset.
	for(var/attempt in 1 to 20)
		if(device.luckynumber7 in actor_effects)
			break
		after(device, 0.1 SECONDS, TYPE_PROC_REF(/obj/item/daredevice, capsule_result), key = "c4_prepare_capsule", with = list(user, /obj/item/spacecasinocash))
		test_time(0.1 SECONDS)
	TEST_ASSERT(device.luckynumber7 in actor_effects, "Actual production randomization reaches an actor-dependent result without fake luck flags")
	var/faults = length(kernel().fault_log)
	after(device, 0.1 SECONDS, TYPE_PROC_REF(/obj/item/daredevice, capsule_result), key = "c4_capsule", with = list(user, /obj/item/spacecasinocash))
	TEST_ASSERT(after_pending(device, "c4_capsule"), "Actual device owns the pending actor-dependent result")
	qdel(user)
	test_time(0.1 SECONDS)
	TEST_ASSERT(!after_pending(device, "c4_capsule"), "Actual result timer fired with a vanished actor")
	TEST_ASSERT_EQUAL(length(kernel().fault_log), faults, "Actor-dependent result with deleted owner produces no callback fault")
	TEST_ASSERT(!QDELETED(device), "Canceled reward retains the actual device for its normal reset")
	TEST_ASSERT(device.luckynumber7 >= 0 && device.luckynumber7 <= 10, "Existing common randomization tail returns to the real normal outcome range")

/// Real jaunt stage and timer boundary; no cast permissions or connected perspective-rendering claim.
/datum/unit_test/c4_jaunt_missing_participant
	var/missing = "target"

/datum/unit_test/c4_jaunt_missing_participant/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	set_global("dview_mob", GLOB.dview_mob)
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	var/turf/surface = test_floor()
	var/datum/spell/targeted/ethereal_jaunt/spell = allocate(/datum/spell/targeted/ethereal_jaunt)
	var/mob/living/carbon/human/target = allocate(/mob/living/carbon/human, surface)
	var/obj/effect/dummy/spell_jaunt/holder = allocate(/obj/effect/dummy/spell_jaunt, surface)
	var/atom/movable/overlay/animation = allocate(/atom/movable/overlay, surface)
	target.forceMove(holder)
	TEST_ASSERT_EQUAL(target.loc, holder, "The actual jaunter is inside its real holder before resurfacing")
	var/faults = length(kernel().fault_log)
	spell.jaunt_resurface(target, holder, animation)
	TEST_ASSERT_EQUAL(target.canmove, 0, "The actual resurface stage suspends target movement")
	if(missing == "target")
		qdel(target)
	else if(missing == "holder")
		qdel(holder)
	else
		qdel(animation)
	test_time(2 SECONDS)
	TEST_ASSERT(!QDELETED(spell), "The timer's independent spell owner survives cleanup")
	TEST_ASSERT(QDELETED(holder), "The actual interrupted reform disposes its surviving holder")
	TEST_ASSERT(QDELETED(animation), "The actual interrupted reform disposes its surviving overlay")
	if(missing != "target")
		TEST_ASSERT(!QDELETED(target), "The surviving real target is not disposed with the holder")
		TEST_ASSERT_EQUAL(target.canmove, 1, "The actual cleanup restores target movement")
		TEST_ASSERT_EQUAL(get_turf(target), surface, "The actual cleanup returns or preserves its floor")
	TEST_ASSERT_EQUAL(length(kernel().fault_log), faults, "Missing participant never reaches an unsafe draw or holder dereference")
	test_time(2 SECONDS) // Let the real resurface steam expire before fixture teardown.

/datum/unit_test/c4_jaunt_missing_participant/holder
	missing = "holder"

/datum/unit_test/c4_jaunt_missing_participant/animation
	missing = "animation"
/// Native timer-boundary isolation: the real victim disappears before landing.
/datum/unit_test/c4_cliff_deleted_victim_timer_boundary

/datum/unit_test/c4_cliff_deleted_victim_timer_boundary/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	test_driver_begin()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	set_global("dview_mob", GLOB.dview_mob)
	var/turf/surface = test_floor()
	TEST_ASSERT(surface, "Actual map supplies a floor")
	var/obj/structure/cliff/cliff = allocate(/obj/structure/cliff, surface)
	var/mob/living/carbon/human/victim = allocate(/mob/living/carbon/human, surface)
	var/faults = length(kernel().fault_log)
	after(cliff, 0.1 SECONDS, TYPE_PROC_REF(/obj/structure/cliff, fall_land), key = "c4_cliff_victim", with = list(victim))
	TEST_ASSERT(after_pending(cliff, "c4_cliff_victim"), "Real cliff owns its landing callback")
	qdel(victim)
	test_time(0.1 SECONDS)
	TEST_ASSERT(!after_pending(cliff, "c4_cliff_victim"), "Landing callback executes rather than remaining pending")
	TEST_ASSERT_EQUAL(length(kernel().fault_log), faults, "Missing victim never enters the unsafe landing injury branch")
	TEST_ASSERT(!QDELETED(cliff) && cliff.loc == surface, "The surviving cliff remains at its original location")

/// Native timer-boundary isolation, before the irreversible sacrifice/revival tail.
/datum/unit_test/c4_cult_raise_deleted_corpse_timer_boundary

/datum/unit_test/c4_cult_raise_deleted_corpse_timer_boundary/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	test_driver_begin()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	set_global("dview_mob", GLOB.dview_mob)
	var/turf/surface = test_floor()
	TEST_ASSERT(surface, "Actual map supplies a floor")
	var/obj/effect/rune/rune = allocate(/obj/effect/rune, surface)
	var/mob/living/carbon/human/caster = allocate(/mob/living/carbon/human, surface)
	var/mob/living/carbon/human/corpse = allocate(/mob/living/carbon/human, surface)
	var/mob/living/carbon/human/offering = allocate(/mob/living/carbon/human, surface)
	var/datum/body/original_body = offering.body
	var/original_stat = offering.stat
	var/faults = length(kernel().fault_log)
	after(rune, 0.1 SECONDS, TYPE_PROC_REF(/obj/effect/rune, raise_finish), key = "c4_cult_raise", with = list(caster, corpse, offering))
	TEST_ASSERT(after_pending(rune, "c4_cult_raise"), "Real rune owns the resurrection continuation")
	qdel(corpse)
	test_time(0.1 SECONDS)
	TEST_ASSERT(!after_pending(rune, "c4_cult_raise"), "Resurrection continuation executes")
	TEST_ASSERT_EQUAL(length(kernel().fault_log), faults, "Missing corpse is rejected before reading its client")
	TEST_ASSERT(!QDELETED(offering) && offering.loc == surface, "The real offering is not gibbed or relocated")
	TEST_ASSERT(offering.body == original_body, "The offering retains its actual original body")
	TEST_ASSERT_EQUAL(offering.stat, original_stat, "The offering's life state remains unchanged")
	TEST_ASSERT(!QDELETED(caster) && !QDELETED(rune), "Caster and rune survive refusal")

/// Real equipped core and spell constructor preserve the failed resurrection cost.
/datum/unit_test/c4_resurrect_deleted_body_timer_boundary

/datum/unit_test/c4_resurrect_deleted_body_timer_boundary/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	test_driver_begin()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	set_global("dview_mob", GLOB.dview_mob)
	var/turf/surface = test_floor()
	TEST_ASSERT(surface, "Actual map supplies a floor")
	var/mob/living/carbon/human/caster = allocate(/mob/living/carbon/human, surface)
	var/mob/living/carbon/human/target = allocate(/mob/living/carbon/human, surface)
	var/obj/item/technomancer_core/core = allocate(/obj/item/technomancer_core, surface)
	TEST_ASSERT(caster.equip_to_slot_if_possible(core, SLOT_ID_BACK), "Actual caster equips a real core through inventory")
	var/obj/item/spell/resurrect/spell = allocate(/obj/item/spell/resurrect, caster)
	TEST_ASSERT(!QDELETED(spell) && spell.owner_ref() == caster && spell.core == core, "Actual spell constructor binds caster and worn core")
	var/original_instability = caster.instability
	var/faults = length(kernel().fault_log)
	after(spell, 0.1 SECONDS, TYPE_PROC_REF(/obj/item/spell/resurrect, resurrect_finish), key = "c4_resurrect_body", with = list(target, caster))
	TEST_ASSERT(after_pending(spell, "c4_resurrect_body"), "Real spell owns resurrection continuation")
	qdel(target)
	test_time(0.1 SECONDS)
	TEST_ASSERT(!after_pending(spell, "c4_resurrect_body"), "Resurrection continuation executes")
	TEST_ASSERT_EQUAL(length(kernel().fault_log), faults, "Deleted original body enters the ordinary failure branch without fault")
	TEST_ASSERT_EQUAL(caster.instability, original_instability + round(10 * core.instability_modifier, 0.1), "Failed resurrection retains its nominal ten instability scaled by the actual core")
	TEST_ASSERT(!QDELETED(spell) && !QDELETED(core) && !QDELETED(caster), "Failure preserves spell, equipped core, and caster")

/// Isolated production callback; the probe observes projectile creation synchronously after the handler.
/datum/unit_test/c4_recycler_deleted_shoot_target_timer_boundary

/datum/unit_test/c4_recycler_deleted_shoot_target_timer_boundary/Run()
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	test_driver_begin()
	defer_cleanup(null, GLOBAL_PROC_REF(test_driver_end))
	set_global("dview_mob", GLOB.dview_mob)
	set_global("om_resolve_nulled", GLOB.om_resolve_nulled)
	var/turf/surface = test_floor()
	var/obj/machinery/maint_recycler/c4_shot_probe/recycler = allocate(/obj/machinery/maint_recycler/c4_shot_probe, surface)
	var/mob/living/carbon/human/victim = allocate(/mob/living/carbon/human, surface)
	var/faults = GLOB.total_runtimes
	after(recycler, 0.1 SECONDS, TYPE_PROC_REF(/obj/machinery/maint_recycler/c4_shot_probe, probe_shoot), key = "c4_recycler_shot", with = list(victim))
	TEST_ASSERT(after_pending(recycler, "c4_recycler_shot"), "The real timer captures its independent victim")
	qdel(victim)
	test_time(0.1 SECONDS)
	TEST_ASSERT(!after_pending(recycler, "c4_recycler_shot"), "The actual delayed callback executes")
	TEST_ASSERT_EQUAL(recycler.observed_new_shots, 0, "Missing target must not create a new stun projectile; the observation starts null")
	TEST_ASSERT_EQUAL(GLOB.total_runtimes, faults, "Missing target produces no callback fault")

/obj/machinery/maint_recycler/c4_shot_probe
	var/observed_new_shots

/obj/machinery/maint_recycler/c4_shot_probe/proc/probe_shoot(mob/victim)
	var/shot_count = 0
	for(var/obj/item/projectile/beam/stun/shot in world)
		shot_count++
	shoot(victim)
	observed_new_shots = -shot_count
	for(var/obj/item/projectile/beam/stun/shot in world)
		observed_new_shots++
