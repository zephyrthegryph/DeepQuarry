// Real status sources drive public machinery operation admission.
/datum/unit_test/round3_living_action_status
	parent_type = /datum/unit_test/read_once_machinery_admission
	abstract_type = /datum/unit_test/round3_living_action_status
	var/status_id

/datum/unit_test/round3_living_action_status/New()
	..()
	status_policies()

/datum/unit_test/round3_living_action_status/proc/action_blocked(mob/living/carbon/human/H, obj/machinery/ai_status_display/D)
	TEST_ASSERT(!stat_value(H, STAT_CAN_ACT), "A real impairment immediately vetoes the composed action stat")
	var/list/row = find_row(op_menu(H, D, H.get_active_hand()), "touch")
	TEST_ASSERT(row && !row["enabled"], "The actual machine Use row is disabled")
	var/datum/op_result/result = test_menu(H, D, "touch")
	TEST_ASSERT_EQUAL(result?.outcome, ACT_REFUSED, "The real public machine operation is refused")
	return TRUE

/datum/unit_test/round3_living_action_status/proc/action_restored(mob/living/carbon/human/H, obj/machinery/ai_status_display/D, obj/item/I)
	TEST_ASSERT_EQUAL(H.stat, CONSCIOUS, "Action recovery is checked only after actual consciousness returns")
	TEST_ASSERT(stat_value(H, STAT_CAN_ACT), "Lifting the last impairment restores the composed stat immediately")
	// Production weakness/paralysis hooks update posture; always recover physical hand custody using its API.
	if(H.get_active_hand() != I)
		TEST_ASSERT(H.put_in_active_hand(I), "The recovered actor re-equips any item dropped by the status")
	var/list/row = find_row(op_menu(H, D, I), "touch")
	TEST_ASSERT(row && row["enabled"], "The same machine Use row re-enables without a clock tick")
	var/datum/op_result/result = test_menu(H, D, "touch")
	TEST_ASSERT_EQUAL(result?.outcome, ACT_COMMITTED, "The recovered actor performs the actual machine operation")
	TEST_ASSERT_EQUAL(H.get_active_hand(), I, "Machine touch preserves the actual item custody")
	return TRUE

/datum/unit_test/round3_living_action_status/run_gate()
	set_global(nameof(GLOB.op_menu_builds), GLOB.op_menu_builds)
	var/mob/living/carbon/human/H = person()
	H.disable_godmode()
	var/obj/machinery/ai_status_display/D = mach(/obj/machinery/ai_status_display, tile(3, 2))
	var/obj/item/I = allocate(/obj/item, H.loc)
	TEST_ASSERT(H.put_in_active_hand(I), "The adjacent human holds an actual item")
	TEST_ASSERT(stat_value(H, STAT_CAN_ACT), "The conscious unimpaired human starts capable")
	TEST_ASSERT(H.status_set(status_id, 2), "The real status API admits the impairment")
	TEST_ASSERT(H.has_status(status_id), "The impairment is effective, not hidden by godmode immunity")
	TEST_ASSERT(action_blocked(H, D), "Effective impairment blocks the real operation")
	H.status_end(status_id)
	TEST_ASSERT(!H.has_status(status_id), "Ending the actual own dose clears the effective status")
	TEST_ASSERT(action_restored(H, D, I), "Lifting the status restores admission and real use")

/datum/unit_test/round3_living_action_status/stun
	status_id = STAT_STUNNED
/datum/unit_test/round3_living_action_status/knockdown
	status_id = STAT_WEAKENED
/datum/unit_test/round3_living_action_status/paralysis
	status_id = STAT_PARALYZED
/datum/unit_test/round3_living_action_status/sleep
	status_id = STAT_SLEEPING

/datum/unit_test/round3_living_action_status/consciousness
/datum/unit_test/round3_living_action_status/consciousness/run_gate()
	set_global(nameof(GLOB.op_menu_builds), GLOB.op_menu_builds)
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/ai_status_display/D = mach(/obj/machinery/ai_status_display, tile(3, 2))
	var/obj/item/I = allocate(/obj/item, H.loc)
	TEST_ASSERT(H.put_in_active_hand(I), "The actor starts with an actual item")
	H.set_stat(UNCONSCIOUS)
	TEST_ASSERT_EQUAL(H.stat, UNCONSCIOUS, "The actual consciousness setter ran")
	TEST_ASSERT(action_blocked(H, D), "Unconsciousness vetoes machine use independently of timed statuses")
	H.set_stat(CONSCIOUS)
	TEST_ASSERT(action_restored(H, D, I), "The consciousness setter restores action admission")
	H.set_stat(DEAD)
	TEST_ASSERT(action_blocked(H, D), "A dead actor is not admitted even without status holds")

/datum/unit_test/round3_living_action_status/independent_sources
/datum/unit_test/round3_living_action_status/independent_sources/run_gate()
	set_global(nameof(GLOB.op_menu_builds), GLOB.op_menu_builds)
	var/mob/living/carbon/human/H = person()
	H.disable_godmode()
	var/obj/machinery/ai_status_display/D = mach(/obj/machinery/ai_status_display, tile(3, 2))
	var/obj/item/I = allocate(/obj/item, H.loc)
	TEST_ASSERT(H.put_in_active_hand(I), "The actual item is held")
	var/datum/external_source = allocate(/datum)
	H.status_set(STAT_STUNNED, 2)
	hold(H, STAT_STUNNED, 1, external_source)
	H.status_end(STAT_STUNNED)
	TEST_ASSERT_NULL(H.status_dose(STAT_STUNNED), "Only SRC_STATUS own dose was ended")
	TEST_ASSERT(H.has_status(STAT_STUNNED), "The independent source still holds stun")
	TEST_ASSERT(action_blocked(H, D), "Ending one source cannot restore admission over another")
	qdel(external_source)
	TEST_ASSERT(!H.has_status(STAT_STUNNED), "Source deletion releases its final ordinary hold")
	TEST_ASSERT(action_restored(H, D, I), "Deletion of the last source restores real operation admission")

/datum/unit_test/round3_living_action_status/immunity
/datum/unit_test/round3_living_action_status/immunity/run_gate()
	set_global(nameof(GLOB.op_menu_builds), GLOB.op_menu_builds)
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/ai_status_display/D = mach(/obj/machinery/ai_status_display, tile(3, 2))
	var/obj/item/I = allocate(/obj/item, H.loc)
	TEST_ASSERT(H.put_in_active_hand(I), "The immune actor really holds the item")
	// Immunity rejects new status holds; place a real hold first, then mask that same source.
	H.disable_godmode()
	var/datum/external_source = allocate(/datum)
	TEST_ASSERT_NOTNULL(hold(H, STAT_STUNNED, 1, external_source), "The nonimmune actor admits an actual independent hold")
	TEST_ASSERT(H.has_status(STAT_STUNNED), "The hold is effective before immunity masks it")
	H.enable_godmode()
	TEST_ASSERT(H.status_immune(STAT_STUNNED), "The fixture starts with real godmode immunity")
	TEST_ASSERT(!H.has_status(STAT_STUNNED), "Immunity zeros effective stun despite its source hold")
	TEST_ASSERT(action_restored(H, D, I), "An ineffective immune status cannot veto action")
	H.disable_godmode()
	TEST_ASSERT(H.has_status(STAT_STUNNED), "Removing immunity exposes the same still-held status")
	TEST_ASSERT(action_blocked(H, D), "The exposed status immediately refuses the public operation")
	H.enable_godmode()
	TEST_ASSERT(!H.has_status(STAT_STUNNED), "Restored immunity masks that same hold")
	TEST_ASSERT(action_restored(H, D, I), "Restoring immunity restores actual action capability")
