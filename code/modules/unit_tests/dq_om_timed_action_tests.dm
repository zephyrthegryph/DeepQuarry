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
	var/datum/om/task/timed/T = om_do_after(user, 1 SECONDS, target, witness, /datum/om_test_entity/proc/timer_hit, list("done"), on_fail = /datum/om_test_entity/proc/timer_hit, fail_args = list("fail"))
	TEST_ASSERT(istype(T), "the timed action starts: [T]")
	TEST_ASSERT_EQUAL(LAZYACCESS(user.do_afters, "\ref[target]"), 1, "the interaction key is counted")
	TEST_ASSERT(istext(om_do_after(user, 1 SECONDS, target, witness, /datum/om_test_entity/proc/timer_hit, list("again"))), "a second action on the same key is refused")
	scheduler_advance(0.5)
	TEST_ASSERT(!length(witness.log), "nothing runs before the deadline")
	scheduler_advance(1)
	TEST_ASSERT_EQUAL(witness.log.Join(","), "done", "on_done runs once at the deadline")
	TEST_ASSERT_EQUAL(T.state, OM_TASK_DONE, "the task is done")
	TEST_ASSERT(!LAZYACCESS(user.do_afters, "\ref[target]"), "the interaction key is released")
	witness.log.Cut()
	TEST_ASSERT_NULL(om_do_after(user, 0, target, witness, /datum/om_test_entity/proc/timer_hit, list("now")), "a zero delay runs at once")
	TEST_ASSERT_EQUAL(witness.log.Join(","), "now", "and calls on_done synchronously")

/datum/unit_test/om/timed_action_cancel_on_move

/datum/unit_test/om/timed_action_cancel_on_move/run_om(list/made)
	var/list/L = timed_setup(made)
	var/mob/living/carbon/human/user = L[1]
	var/obj/item/target = L[2]
	var/datum/om_test_entity/witness = entity(made)
	var/datum/om/task/timed/T = om_do_after(user, 1 SECONDS, target, witness, /datum/om_test_entity/proc/timer_hit, list("done"), on_fail = /datum/om_test_entity/proc/timer_hit, fail_args = list("fail"))
	TEST_ASSERT(istype(T), "the timed action starts: [T]")
	var/turf/next = get_step(user, EAST)
	user.forceMove(next)
	scheduler_advance(0.2)
	TEST_ASSERT_EQUAL(T.state, OM_TASK_CANCELLED, "moving cancels")
	TEST_ASSERT_EQUAL(T.reason, "moved", "with the reason")
	scheduler_advance(2)
	TEST_ASSERT_EQUAL(witness.log.Join(","), "fail", "on_fail ran, on_done never")

	witness.log.Cut()
	var/datum/om/task/timed/F = om_do_after(user, 1 SECONDS, target, witness, /datum/om_test_entity/proc/timer_hit, list("done"), IGNORE_USER_LOC_CHANGE | IGNORE_TARGET_LOC_CHANGE)
	user.forceMove(get_step(next, WEST))
	scheduler_advance(1.5)
	TEST_ASSERT_EQUAL(F.state, OM_TASK_DONE, "IGNORE_USER_LOC_CHANGE keeps it running")

	witness.log.Cut()
	var/obj/item/held = allocate(/obj/item/tool/wrench)
	user.put_in_active_hand(held)
	var/datum/om/task/timed/H = om_do_after(user, 1 SECONDS, target, witness, /datum/om_test_entity/proc/timer_hit, list("done"))
	user.drop_from_inventory(held)
	scheduler_advance(0.2)
	TEST_ASSERT_EQUAL(H.state, OM_TASK_CANCELLED, "changing the held item cancels")

/datum/unit_test/om/timed_action_cancel_on_delete

/datum/unit_test/om/timed_action_cancel_on_delete/run_om(list/made)
	var/list/L = timed_setup(made)
	var/mob/living/carbon/human/user = L[1]
	var/obj/item/target = L[2]
	var/datum/om_test_entity/witness = entity(made)
	var/datum/om/task/timed/T = om_do_after(user, 1 SECONDS, target, witness, /datum/om_test_entity/proc/timer_hit, list("done"), on_fail = /datum/om_test_entity/proc/timer_hit, fail_args = list("fail"))
	qdel(target)
	TEST_ASSERT_EQUAL(T.state, OM_TASK_CANCELLED, "deleting the target cancels at once")
	TEST_ASSERT_EQUAL(witness.log.Join(","), "fail", "on_fail ran")
	TEST_ASSERT(!LAZYLEN(user.do_afters), "the interaction key is released")

	witness.log.Cut()
	var/obj/item/other = allocate(/obj/item/stack/material/steel, get_turf(user))
	var/datum/om_test_entity/arg = entity(made)
	om_do_after(user, 1 SECONDS, other, witness, /datum/om_test_entity/proc/timer_hit, list("done", arg))
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
	var/datum/om/task/timed/T = om_do_after(user, 1 SECONDS, target, witness, /datum/om_test_entity/proc/timer_hit, list("mine"), claims = TRUE)
	TEST_ASSERT(istype(T), "the claiming action starts: [T]")
	var/refused = om_do_after(other, 1 SECONDS, target, witness, /datum/om_test_entity/proc/timer_hit, list("theirs"), claims = TRUE)
	TEST_ASSERT(istext(refused), "a second claim is refused with a reason: [refused]")
	var/datum/om/task/timed/shared = om_do_after(other, 1 SECONDS, target, witness, /datum/om_test_entity/proc/timer_hit, list("shared"))
	TEST_ASSERT(istype(shared), "a non-claiming action on the same target still starts")
	scheduler_advance(1.5)
	TEST_ASSERT(("mine" in witness.log) && ("shared" in witness.log), "both complete")
	var/datum/om/task/timed/next = om_do_after(other, 1 SECONDS, target, witness, /datum/om_test_entity/proc/timer_hit, list("next"), claims = TRUE)
	TEST_ASSERT(istype(next), "the claim is released on completion: [next]")

/datum/om_test_entity/flagged
	var/busy = FALSE

/// A flag set before a converted action is owned by it: when the action's
/// timer is dropped (an argument was deleted), the flag still clears itself,
/// and a stale expiry never clears a newer hold.
/datum/unit_test/om/timed_action_flag_owned

/datum/unit_test/om/timed_action_flag_owned/run_om(list/made)
	var/datum/om_test_entity/flagged/holder = entity(made, /datum/om_test_entity/flagged)
	var/datum/om_test_entity/arg = entity(made)
	om_flag_hold(holder, "busy", 2 SECONDS)
	TEST_ASSERT(holder.busy, "the hold sets the flag")
	// The continuation that would clear it is dropped with its deleted argument.
	om_after(holder, 1 SECOND, /datum/om_test_entity/proc/timer_hit, arg)
	qdel(arg)
	scheduler_advance(1.5)
	TEST_ASSERT(holder.busy, "the flag is still held before its expiry")
	scheduler_advance(1)
	TEST_ASSERT(!holder.busy, "a dropped continuation doesn't leave the flag set forever")

	om_flag_hold(holder, "busy", 1 SECOND)
	holder.busy = FALSE // the continuation ran and cleared it
	om_flag_hold(holder, "busy", 5 SECONDS) // a newer action holds it again
	scheduler_advance(1.5)
	TEST_ASSERT(holder.busy, "a stale expiry doesn't clear a newer hold")
