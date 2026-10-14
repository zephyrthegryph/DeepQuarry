/// Actual equipped hazard rig loading respects original grenade release and the five-round family capacity.
/datum/unit_test/round2_rig_grenade_checked_load
	parent_type = /datum/unit_test/dq_p2_engine

/datum/unit_test/round2_rig_grenade_checked_load/run_gate()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/rig/hazard/equipped/rig = allocate(/obj/item/rig/hazard/equipped, T)
	var/obj/item/rig_module/grenade_launcher/launcher
	for(var/obj/item/rig_module/module as anything in rig.installed_modules)
		if(module.type == /obj/item/rig_module/grenade_launcher)
			launcher = module
	TEST_ASSERT(launcher, "actual equipped hazard rig initializes its original grenade launcher")
	TEST_ASSERT_EQUAL(launcher.vars[nameof(launcher.holder)], rig, "actual initialized launcher links exact original rig")
	TEST_ASSERT(!rig.open, "actual closed rig dispatches reloads to installed modules")
	var/datum/rig_charge/flash = launcher.charges["flashbang"]
	var/datum/rig_charge/smoke = launcher.charges["smoke bomb"]
	var/datum/rig_charge/emp = launcher.charges["EMP grenade"]
	TEST_ASSERT(flash && smoke && emp, "actual launcher initializes all three declared ammunition families")
	TEST_ASSERT_EQUAL(flash.charges, 3, "actual flashbang magazine starts with three rounds")
	TEST_ASSERT_EQUAL(flash.product_type, /obj/item/grenade/flashbang, "actual flash magazine accepts canonical flashbangs")
	var/obj/item/grenade/flashbang/original = allocate(/obj/item/grenade/flashbang, T)
	TEST_ASSERT(user.put_in_active_hand(original), "actor holds original unarmed flashbang")
	add_trait(original, TRAIT_NODROP, "round2_rig_grenade_checked_load")
	TEST_ASSERT(user.release_refusal(original, user), "actual inventory refuses sticky original grenade")
	test_click(user, rig, original)
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(flash.charges, 3, "refused original consumption grants no magazine ammunition")
	TEST_ASSERT(!QDELETED(original) && original.loc == user, "refused load preserves original grenade alive in inventory")
	TEST_ASSERT_EQUAL(user.get_active_hand(), original, "refused load preserves exact original hand")
	remove_trait(original, TRAIT_NODROP, "round2_rig_grenade_checked_load")
	test_click(user, rig, original)
	test_time(1 SECOND)
	TEST_ASSERT(QDELETED(original), "allowed load consumes exact original grenade")
	TEST_ASSERT_EQUAL(user.get_active_hand(), null, "allowed consumption clears original hand")
	TEST_ASSERT_EQUAL(flash.charges, 4, "one consumed original grants exactly one magazine round")
	var/obj/item/grenade/flashbang/last = allocate(/obj/item/grenade/flashbang, T)
	TEST_ASSERT(user.put_in_active_hand(last), "actor holds exact final capacity ingredient")
	test_click(user, rig, last)
	test_time(1 SECOND)
	TEST_ASSERT(QDELETED(last), "last available slot consumes exact original ingredient")
	TEST_ASSERT_EQUAL(flash.charges, 5, "actual magazine reaches exact declared reload ceiling")
	var/obj/item/grenade/flashbang/excess = allocate(/obj/item/grenade/flashbang, T)
	TEST_ASSERT(user.put_in_active_hand(excess), "actor holds exact excess ingredient")
	test_click(user, rig, excess)
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(flash.charges, 5, "full magazine refuses without increasing capacity")
	TEST_ASSERT(!QDELETED(excess) && excess.loc == user, "full magazine preserves original excess grenade")
	TEST_ASSERT_EQUAL(user.get_active_hand(), excess, "full magazine preserves exact excess hand")
	TEST_ASSERT_EQUAL(smoke.charges, 3, "flashbang loading preserves original smoke ammunition")
	TEST_ASSERT_EQUAL(emp.charges, 3, "flashbang loading preserves original EMP ammunition")
