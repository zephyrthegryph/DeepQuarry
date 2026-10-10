// The hand gate audit (doc/rewrite/intended_changes.md "The hand gate audit"). Every hand() op is refused for an actor who is unconscious or stunned
// (op_hand_capable()), and without ungated() one on a machine also for a machine that does not work. What a down or restrained actor may still do is not
// a hand() op: the Resist verb starts system-origin ops (cuff_remove, cuff_break, buckle_escape, jacket_escape, break_out), which skip the hand gate.
// These tests pin both halves: the touch is refused, the escape is not.

/datum/unit_test/dq_hand_gate_audit
	abstract_type = /datum/unit_test/dq_hand_gate_audit
	parent_type = /datum/unit_test/dq_timed_pin

/// Every hand binding of every compiled table: the number of ops with one, those that say ungated(), and the ones whose actor is the thing they free.
/datum/unit_test/dq_hand_gate_audit/proc/hand_ops()
	var/list/found = list()
	for(var/type in type_table_cache())
		var/datum/type_table/T = type_table_cache()[type]
		if(!T)
			continue
		for(var/datum/op_plan/P as anything in op_index_of_table(T).ordered)
			for(var/datum/entry/part/bind/B as anything in P.bindings)
				if(B.bind_kind == BIND_HAND)
					found["[type] [P.key]"] = !!LAZYACCESS(P.selects, "ungated")
					break
	return found

/// The ops a restrained, stunned or down actor still starts through the Resist verb have no hand binding: the hand gate never sees them.
/datum/unit_test/dq_hand_gate_audit/escapes_are_not_hand_ops

/datum/unit_test/dq_hand_gate_audit/escapes_are_not_hand_ops/run_pin()
	var/mob/living/carbon/human/H = person()
	var/obj/structure/closet/C = allocate(/obj/structure/closet, run_loc_floor_bottom_left)
	var/list/escapes = list("cuff_remove", "cuff_break", "buckle_escape", "jacket_escape")
	for(var/key in escapes)
		var/datum/op_plan/P = op_plan_for(H, key)
		TEST_ASSERT(!isnull(P), "[key] exists on a human")
		for(var/datum/entry/part/bind/B as anything in P.bindings)
			TEST_ASSERT(B.bind_kind != BIND_HAND, "[key] is not a hand op: the hand gate must never refuse it")
	var/datum/op_plan/break_out = op_plan_for(C, "break_out")
	TEST_ASSERT(!isnull(break_out), "a closet has break_out")
	for(var/datum/entry/part/bind/B as anything in break_out.bindings)
		TEST_ASSERT(B.bind_kind != BIND_HAND, "break_out is not a hand op")
	var/list/ops = hand_ops()
	TEST_ASSERT(length(ops) > 0, "the compiled tables hold hand ops")
	var/ungated = 0
	for(var/key in ops)
		if(ops[key])
			ungated++
	log_test("HAND GATE AUDIT: [length(ops)] hand ops in the built tables, [ungated] ungated(), [length(ops) - ungated] behind the machine half")

/// A cuffed, conscious mob can resist its cuffs (the hand gate does not see the resist).
/datum/unit_test/dq_hand_gate_audit/cuffed_mob_can_resist

/datum/unit_test/dq_hand_gate_audit/cuffed_mob_can_resist/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/item/handcuffs/fuzzy/C = allocate(/obj/item/handcuffs/fuzzy, run_loc_floor_bottom_left)
	TEST_ASSERT(user.equip_to_slot(C, SLOT_ID_HANDCUFFED), "setup: cuffed")
	TEST_ASSERT(user.restrained(), "setup: restrained")
	user.resist()
	TEST_ASSERT(!isnull(running(user)), "a cuffed mob's resist starts the cuff op")
	test_time(11 SECONDS)
	TEST_ASSERT_NULL(user.get_equipped_item(SLOT_ID_HANDCUFFED), "the cuffs come off")

/// A buckled, conscious, cuffed mob can unbuckle itself by resisting; a buckled, stunned mob cannot use a machine; the escape does not need a hand.
/datum/unit_test/dq_hand_gate_audit/buckled_cuffed_mob_unbuckles_but_stunned_buckled_mob_cannot_touch

/datum/unit_test/dq_hand_gate_audit/buckled_cuffed_mob_unbuckles_but_stunned_buckled_mob_cannot_touch/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/bed/roller/bed = allocate(/obj/structure/bed/roller, run_loc_floor_bottom_left)
	var/obj/machinery/p2_hand_machine/M = allocate(/obj/machinery/p2_hand_machine, get_step(run_loc_floor_bottom_left, EAST))
	var/obj/item/handcuffs/C = allocate(/obj/item/handcuffs, run_loc_floor_bottom_left)
	TEST_ASSERT(bed.buckle_mob(user, forced = TRUE), "setup: buckled")
	user.status_set(STAT_STUNNED, 5)
	test_click(user, M)
	TEST_ASSERT_EQUAL(M.touched, 0, "a stunned, buckled mob cannot use the machine")
	user.status_set(STAT_STUNNED, 0)
	TEST_ASSERT(user.equip_to_slot(C, SLOT_ID_HANDCUFFED), "setup: cuffed")
	user.resist()
	TEST_ASSERT(!isnull(running(user)), "a buckled, cuffed, conscious mob's resist starts the unbuckle")
	test_time(2.1 MINUTES)
	TEST_ASSERT_NULL(user.buckled_to(), "it is unbuckled at the end")

/// Stunned (not out) and buckled and cuffed: the Resist verb still starts the escape, which is not a hand op.
/datum/unit_test/dq_hand_gate_audit/stunned_buckled_cuffed_mob_can_still_start_the_escape

/datum/unit_test/dq_hand_gate_audit/stunned_buckled_cuffed_mob_can_still_start_the_escape/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/bed/roller/bed = allocate(/obj/structure/bed/roller, run_loc_floor_bottom_left)
	var/obj/item/handcuffs/C = allocate(/obj/item/handcuffs, run_loc_floor_bottom_left)
	TEST_ASSERT(bed.buckle_mob(user, forced = TRUE), "setup: buckled")
	TEST_ASSERT(user.equip_to_slot(C, SLOT_ID_HANDCUFFED), "setup: cuffed")
	user.status_set(STAT_STUNNED, 50)
	user.resist()
	TEST_ASSERT(!isnull(running(user)), "the escape starts for a stunned mob")

/// An unconscious mob starts nothing: resisting needs a mind awake (the verb's own rule, unchanged).
/datum/unit_test/dq_hand_gate_audit/unconscious_mob_starts_no_escape

/datum/unit_test/dq_hand_gate_audit/unconscious_mob_starts_no_escape/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/bed/roller/bed = allocate(/obj/structure/bed/roller, run_loc_floor_bottom_left)
	var/obj/item/handcuffs/C = allocate(/obj/item/handcuffs, run_loc_floor_bottom_left)
	TEST_ASSERT(bed.buckle_mob(user, forced = TRUE), "setup: buckled")
	user.equip_to_slot(C, SLOT_ID_HANDCUFFED)
	user.set_stat(UNCONSCIOUS)
	user.resist()
	TEST_ASSERT_NULL(running(user), "an unconscious mob does not start an escape")
	user.set_stat(CONSCIOUS)

/// A cuffed mob shut in a sealed closet can break out.
/datum/unit_test/dq_hand_gate_audit/shut_in_mob_can_break_out

/datum/unit_test/dq_hand_gate_audit/shut_in_mob_can_break_out/run_pin()
	var/mob/living/carbon/human/user = person()
	var/obj/structure/closet/C = allocate(/obj/structure/closet, get_step(run_loc_floor_bottom_left, EAST))
	user.forceMove(C)
	set_welded(C, TRUE)
	var/obj/item/handcuffs/cuffs = allocate(/obj/item/handcuffs, run_loc_floor_bottom_left)
	TEST_ASSERT(user.equip_to_slot(cuffs, SLOT_ID_HANDCUFFED), "setup: cuffed")
	user.resist()
	TEST_ASSERT(!isnull(running(user)), "a cuffed shut-in mob's resist starts the break-out")
	test_time(C.breakout_time MINUTES + 1 SECONDS)
	TEST_ASSERT(user.loc != C, "it is out of the closet at the end")
