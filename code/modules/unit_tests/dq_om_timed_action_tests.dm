// Timed actions (code/datums/om/timed_action.dm): the task that replaced do_after.

/datum/unit_test/om/proc/timed_setup(list/made)
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human)
	var/obj/item/target = allocate(/obj/item/stack/material/steel, get_turf(user))
	return list(user, target)

/datum/unit_test/om/timed_action_completes

/datum/unit_test/om/timed_action_completes/run_om(list/made)
	var/list/L = timed_setup(made)
	var/mob/living/carbon/human/user = L[1]
	var/obj/item/target = L[2]
	var/datum/om_test_entity/witness = entity(made)
	var/datum/task/timed/T = task_timed(user, 1 SECONDS, target, witness, /datum/om_test_entity/proc/timer_hit, list("done"), on_fail = /datum/om_test_entity/proc/timer_hit, fail_args = list("fail"))
	TEST_ASSERT(istype(T), "the timed action starts: [T]")
	TEST_ASSERT_EQUAL(LAZYACCESS(user.do_afters, "\ref[target]"), 1, "the interaction key is counted")
	TEST_ASSERT(istext(task_timed(user, 1 SECONDS, target, witness, /datum/om_test_entity/proc/timer_hit, list("again"))), "a second action on the same key is refused")
	scheduler_advance(0.5)
	TEST_ASSERT(!length(witness.log), "nothing runs before the deadline")
	scheduler_advance(1)
	TEST_ASSERT_EQUAL(jointext(witness.log || list(), ","), "done", "on_done runs once at the deadline")
	TEST_ASSERT_EQUAL(T.state, TASK_DONE, "the task is done")
	TEST_ASSERT(!LAZYACCESS(user.do_afters, "\ref[target]"), "the interaction key is released")
	LAZYCLEARLIST(witness.log)
	TEST_ASSERT_NULL(task_timed(user, 0, target, witness, /datum/om_test_entity/proc/timer_hit, list("now")), "a zero delay runs at once")
	TEST_ASSERT_EQUAL(jointext(witness.log || list(), ","), "now", "and calls on_done synchronously")

/datum/unit_test/om/timed_action_cancel_on_move

/datum/unit_test/om/timed_action_cancel_on_move/run_om(list/made)
	var/list/L = timed_setup(made)
	var/mob/living/carbon/human/user = L[1]
	var/obj/item/target = L[2]
	var/datum/om_test_entity/witness = entity(made)
	var/datum/task/timed/T = task_timed(user, 1 SECONDS, target, witness, /datum/om_test_entity/proc/timer_hit, list("done"), on_fail = /datum/om_test_entity/proc/timer_hit, fail_args = list("fail"))
	TEST_ASSERT(istype(T), "the timed action starts: [T]")
	var/turf/next = get_step(user, EAST)
	user.forceMove(next)
	scheduler_advance(0.2)
	TEST_ASSERT_EQUAL(T.state, TASK_CANCELLED, "moving cancels")
	TEST_ASSERT_EQUAL(T.reason, "moved", "with the reason")
	scheduler_advance(2)
	TEST_ASSERT_EQUAL(jointext(witness.log || list(), ","), "fail", "on_fail ran, on_done never")

	LAZYCLEARLIST(witness.log)
	var/datum/task/timed/F = task_timed(user, 1 SECONDS, target, witness, /datum/om_test_entity/proc/timer_hit, list("done"), IGNORE_USER_LOC_CHANGE | IGNORE_TARGET_LOC_CHANGE)
	user.forceMove(get_step(next, WEST))
	scheduler_advance(1.5)
	TEST_ASSERT_EQUAL(F.state, TASK_DONE, "IGNORE_USER_LOC_CHANGE keeps it running")

	LAZYCLEARLIST(witness.log)
	var/obj/item/held = allocate(/obj/item/tool/wrench)
	user.put_in_active_hand(held)
	var/datum/task/timed/H = task_timed(user, 1 SECONDS, target, witness, /datum/om_test_entity/proc/timer_hit, list("done"))
	user.drop_from_inventory(held)
	scheduler_advance(0.2)
	TEST_ASSERT_EQUAL(H.state, TASK_CANCELLED, "changing the held item cancels")

/datum/unit_test/om/timed_action_cancel_on_delete

/datum/unit_test/om/timed_action_cancel_on_delete/run_om(list/made)
	var/list/L = timed_setup(made)
	var/mob/living/carbon/human/user = L[1]
	var/obj/item/target = L[2]
	var/datum/om_test_entity/witness = entity(made)
	var/datum/task/timed/T = task_timed(user, 1 SECONDS, target, witness, /datum/om_test_entity/proc/timer_hit, list("done"), on_fail = /datum/om_test_entity/proc/timer_hit, fail_args = list("fail"))
	qdel(target)
	TEST_ASSERT_EQUAL(T.state, TASK_CANCELLED, "deleting the target cancels at once")
	TEST_ASSERT_EQUAL(jointext(witness.log || list(), ","), "fail", "on_fail ran")
	TEST_ASSERT(!LAZYLEN(user.do_afters), "the interaction key is released")

	LAZYCLEARLIST(witness.log)
	var/obj/item/other = allocate(/obj/item/stack/material/steel, get_turf(user))
	var/datum/om_test_entity/arg = entity(made)
	task_timed(user, 1 SECONDS, other, witness, /datum/om_test_entity/proc/timer_hit, list("done", arg))
	qdel(arg)
	scheduler_advance(1.5)
	TEST_ASSERT(!length(witness.log), "a deleted argument drops on_done")

/datum/unit_test/om/timed_action_claim_refusal

/datum/unit_test/om/timed_action_claim_refusal/run_om(list/made)
	var/list/L = timed_setup(made)
	var/mob/living/carbon/human/user = L[1]
	var/obj/item/target = L[2]
	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human)
	var/datum/om_test_entity/witness = entity(made)
	var/datum/task/timed/T = task_timed(user, 1 SECONDS, target, witness, /datum/om_test_entity/proc/timer_hit, list("mine"), claims = TRUE)
	TEST_ASSERT(istype(T), "the claiming action starts: [T]")
	var/refused = task_timed(other, 1 SECONDS, target, witness, /datum/om_test_entity/proc/timer_hit, list("theirs"), claims = TRUE)
	TEST_ASSERT(istext(refused), "a second claim is refused with a reason: [refused]")
	var/datum/task/timed/shared = task_timed(other, 1 SECONDS, target, witness, /datum/om_test_entity/proc/timer_hit, list("shared"))
	TEST_ASSERT(istype(shared), "a non-claiming action on the same target still starts")
	scheduler_advance(1.5)
	TEST_ASSERT(("mine" in witness.log) && ("shared" in witness.log), "both complete")
	var/datum/task/timed/next = task_timed(other, 1 SECONDS, target, witness, /datum/om_test_entity/proc/timer_hit, list("next"), claims = TRUE)
	TEST_ASSERT(istype(next), "the claim is released on completion: [next]")

/// "Busy" is a claim, not a flag: a timed action claims the thing doing the work (busy = X);
/// task_busy(X) holds exactly while the action runs, a second claiming action is refused, and the
/// claim is released on completion, on cancel and when the action's other end is deleted.
/datum/unit_test/om/timed_action_busy_claims

/datum/unit_test/om/timed_action_busy_claims/run_om(list/made)
	var/list/L = timed_setup(made)
	var/mob/living/carbon/human/user = L[1]
	var/obj/item/target = L[2]
	var/datum/om_test_entity/witness = entity(made)
	var/obj/item/tool = allocate(/obj/item/tool/wrench, get_turf(user))
	TEST_ASSERT(!task_busy(tool), "nothing claims the tool yet")
	var/datum/task/timed/T = task_timed(user, 1 SECONDS, target, witness, /datum/om_test_entity/proc/timer_hit, list("done"), busy = tool)
	TEST_ASSERT(istype(T), "the claiming action starts: [T]")
	TEST_ASSERT(task_busy(tool), "the running action claims its tool")
	TEST_ASSERT_EQUAL(task_claiming(tool), T, "task_claiming() finds the action")
	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human)
	var/obj/item/other_target = allocate(/obj/item/stack/material/steel, get_turf(other))
	TEST_ASSERT_EQUAL(task_timed(other, 1 SECONDS, other_target, witness, /datum/om_test_entity/proc/timer_hit, list("second"), busy = tool), "busy", "a second action on a busy tool is refused")
	TEST_ASSERT(!task_busy(target), "a busy claim doesn't make the target in use")
	scheduler_advance(1.5)
	TEST_ASSERT_EQUAL(T.state, TASK_DONE, "the action completes")
	TEST_ASSERT(!task_busy(tool), "completion releases the claim")

	// Cancel releases it.
	var/datum/task/timed/C = task_timed(user, 1 SECONDS, target, witness, /datum/om_test_entity/proc/timer_hit, list("cancelled"), busy = tool)
	TEST_ASSERT(task_busy(tool), "claimed again")
	user.forceMove(get_step(user, EAST))
	scheduler_advance(0.2)
	TEST_ASSERT_EQUAL(C.state, TASK_CANCELLED, "moving cancels")
	TEST_ASSERT(!task_busy(tool), "cancel releases the claim")

	// Deleting the claimed thing ends the action; deleting the target releases the claim.
	var/obj/item/doomed = allocate(/obj/item/tool/wrench, get_turf(user))
	var/datum/task/timed/D = task_timed(user, 1 SECONDS, target, witness, /datum/om_test_entity/proc/timer_hit, list("doomed"), IGNORE_USER_LOC_CHANGE, busy = doomed)
	qdel(doomed)
	TEST_ASSERT_EQUAL(D.state, TASK_CANCELLED, "deleting the claimed thing cancels the action")
	var/datum/task/timed/E = task_timed(user, 1 SECONDS, target, witness, /datum/om_test_entity/proc/timer_hit, list("gone"), IGNORE_USER_LOC_CHANGE, busy = tool)
	qdel(target)
	TEST_ASSERT_EQUAL(E.state, TASK_CANCELLED, "deleting the target cancels the action")
	TEST_ASSERT(!task_busy(tool), "and releases the claim")

/// task_hold_busy(): an action whose continuation is a timer holds its worker busy for a duration; the
/// hold ends by its deadline, by task_release_busy(), or when the worker is deleted, and runs on_end.
/datum/unit_test/om/timed_action_hold

/datum/unit_test/om/timed_action_hold/run_om(list/made)
	var/datum/om_test_entity/holder = entity(made)
	var/datum/task/H = task_hold_busy(holder, 1 SECOND, /datum/om_test_entity/proc/timer_hit)
	TEST_ASSERT(istype(H), "the hold starts: [H]")
	TEST_ASSERT(task_busy(holder), "the hold claims its holder")
	TEST_ASSERT(istext(task_hold_busy(holder, 1 SECOND)), "a second hold is refused while busy")
	scheduler_advance(1.5)
	TEST_ASSERT(!task_busy(holder), "the hold ends at its deadline")
	TEST_ASSERT_EQUAL(length(holder.log), 1, "on_end ran once")
	task_hold_busy(holder, 5 SECONDS)
	TEST_ASSERT(task_release_busy(holder), "task_release_busy() ends a hold early")
	TEST_ASSERT(!task_busy(holder), "released")
