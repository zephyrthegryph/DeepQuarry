/// Public thrower entry with a target removed while its movement is pending.
/datum/unit_test/retire_thrower_deleted_target_timer

/datum/unit_test/retire_thrower_deleted_target_timer/Run()
	test_driver_begin()
	set_global("dview_mob", GLOB.dview_mob)
	exercise_thrower()
	test_driver_end()

/datum/unit_test/retire_thrower_deleted_target_timer/proc/exercise_thrower()
	var/turf/surface = test_floor()
	TEST_ASSERT(surface, "The actual map supplies a floor for the thrower")
	var/obj/item/target = allocate(/obj/item, surface)
	var/obj/effect/step_trigger/thrower/thrower = allocate(/obj/effect/step_trigger/thrower, surface)
	thrower.Trigger(target)
	TEST_ASSERT(target in thrower.affecting, "The public thrower entry registers its real target before movement")
	qdel(target)
	test_time(0.2 SECONDS)
	TEST_ASSERT(!QDELETED(thrower), "The thrower survives removal of its pending target")
	TEST_ASSERT_EQUAL(LAZYLEN(thrower.affecting), 0, "The stale throw finishes without retaining an affected target")

/// Native click entry and the real implant's delayed reagent transfer.
/datum/unit_test/retire_implantcase_syringe_timer
	var/delete_syringe = FALSE

/datum/unit_test/retire_implantcase_syringe_timer/Run()
	test_driver_begin()
	set_global("dview_mob", GLOB.dview_mob)
	exercise_filling()
	test_driver_end()

/datum/unit_test/retire_implantcase_syringe_timer/proc/exercise_filling()
	var/turf/surface = test_floor()
	TEST_ASSERT(surface, "The actual map supplies a floor for implant filling")
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, surface)
	var/obj/item/implantcase/chem/case = allocate(/obj/item/implantcase/chem, surface)
	var/obj/item/reagent_containers/syringe/syringe = allocate(/obj/item/reagent_containers/syringe, surface)
	TEST_ASSERT(case.imp && case.imp.allow_reagents && case.imp.reagents, "The real chemical case constructs a reagent implant")
	TEST_ASSERT(case.imp.reagents.maximum_volume - case.imp.reagents.total_volume >= 5, "The actual implant has room for all five transferred units")
	syringe.reagents.add_reagent(REAGENT_ID_WATER, 5)
	TEST_ASSERT_EQUAL(syringe.reagents.total_volume, 5, "The real syringe holds five units of water")
	TEST_ASSERT(actor.put_in_active_hand(syringe), "The real inventory entry puts the syringe in the actor's hand")
	var/initial_volume = case.imp.reagents.total_volume
	var/datum/op_result/result = test_click(actor, case, syringe)
	TEST_ASSERT(result && result.key == "fill_from_syringe" && !(result.outcome & ACT_REFUSED), "The input inbox resolves the actual implant-case filling operation")
	TEST_ASSERT_EQUAL(case.imp.reagents.total_volume, initial_volume, "The operation schedules filling instead of transferring immediately")
	if(delete_syringe)
		qdel(syringe)
	test_time(0.6 SECONDS)
	TEST_ASSERT(!QDELETED(case) && case.imp && case.imp.reagents, "The timer preserves its case and real chemical implant")
	TEST_ASSERT_EQUAL(case.imp.reagents.total_volume, initial_volume + (delete_syringe ? 0 : 5), "A live syringe transfers exactly five units and a deleted syringe transfers none")
	if(!delete_syringe)
		TEST_ASSERT_EQUAL(syringe.reagents.total_volume, 0, "The scheduled transfer removes the actual five units from the syringe")

/datum/unit_test/retire_implantcase_syringe_timer/deleted
	delete_syringe = TRUE

/// Real fancy dispenser, its constructor-created catalog, and public dispensing.
/datum/unit_test/retire_fancy_gear_setting_timer
	var/delete_setting = FALSE

/datum/unit_test/retire_fancy_gear_setting_timer/Run()
	test_driver_begin()
	set_global("dview_mob", GLOB.dview_mob)
	var/catalog_key = "[/obj/machinery/gear_dispenser/suit_fancy]"
	var/had_tracking_entry = (catalog_key in GLOB.gear_distributed_to)
	var/list/previous_tracking = GLOB.gear_distributed_to[catalog_key]
	exercise_dispensing()
	if(had_tracking_entry)
		GLOB.gear_distributed_to[catalog_key] = previous_tracking
	else
		GLOB.gear_distributed_to -= catalog_key
	test_driver_end()

/datum/unit_test/retire_fancy_gear_setting_timer/proc/exercise_dispensing()
	var/turf/surface = test_floor()
	TEST_ASSERT(surface, "Actual test map supplies a floor")
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, surface)
	var/obj/machinery/gear_dispenser/suit_fancy/dispenser = allocate(/obj/machinery/gear_dispenser/suit_fancy, surface)
	TEST_ASSERT(dispenser.door, "Actual fancy constructor creates the animation door")
	TEST_ASSERT_EQUAL(LAZYLEN(dispenser.dispenses), 1, "Actual default catalog has its single real trash setting")
	var/datum/gear_disp/setting = dispenser.dispenses["???"]
	TEST_ASSERT(istype(setting, /datum/gear_disp/trash), "Actual catalog resolves its constructor-created trash setting")
	own(setting)
	var/obj/item/card/emag/emag = allocate(/obj/item/card/emag, surface)
	TEST_ASSERT(actor.put_in_active_hand(emag), "Actual inventory holds the real emag")
	var/datum/op_result/result = test_click(actor, dispenser, emag)
	TEST_ASSERT(result && !(result.outcome & ACT_REFUSED) && dispenser.emagged, "Actual click emags the fancy dispenser before dispensing")
	var/initial_flags = dispenser.dispenser_flags
	var/initial_amount = setting.amount
	dispenser.dispense(setting, actor, TRUE)
	TEST_ASSERT_EQUAL(dispenser.held_gear_disp(), setting, "Public dispense retains the actual catalog setting")
	TEST_ASSERT_EQUAL(setting.amount, initial_amount, "Actual unlimited default catalog keeps its stock amount")
	if(delete_setting)
		qdel(setting)
	test_time(5.1 SECONDS)
	TEST_ASSERT_EQUAL(dispenser.held_gear_disp(), delete_setting ? null : setting, "The actual pending animation retains only its live catalog setting")
	TEST_ASSERT_EQUAL(dispenser.dispenser_flags, initial_flags, "The actual fancy animation preserves its existing flags")
	TEST_ASSERT(dispenser.emagged, "Emag state remains pending until the completion handler")
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(dispenser.dispenser_flags, initial_flags, "Completion preserves the original nonbusy flags")
	TEST_ASSERT(!dispenser.emagged, "Completion clears the real emag state even when its setting vanished")
	TEST_ASSERT_EQUAL(dispenser.held_gear_disp(), delete_setting ? null : setting, "Deleted catalog references clear while a live setting remains available")

/datum/unit_test/retire_fancy_gear_setting_timer/deleted
	delete_setting = TRUE
