// Fixtures of the timed-action forms: starts(), plays(at_start), msg_text(), asks(ends_on_no), captures() on a wait, claims(), ORIGIN_SYSTEM pendings,
// hold_busy() and every_running(). Compiled under UNIT_TESTS only; code/modules/unit_tests/dq_timed_forms_tests.dm drives them.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

MSG_DEF_SELF(tf/begins, "You begin the long work.")
MSG_DEF_SELF(tf/masked, "Take the mask off first.")

/obj/tf_site
	name = "timed forms site"
	var/started = 0
	var/done = 0
	var/ended = 0
	var/amount = 1

TRACKED(/obj/tf_site, amount)

CAPABILITIES(/obj/tf_site)
	op("start", menu(), begins(MSG(tf/begins)), starts(PROC_REF(on_start)), wait(3 SECONDS), then(PROC_REF(finished)))
	op("dyn", menu(), begins(PROC_REF(dyn_text)), wait(1 SECOND), then(PROC_REF(finished)))
	op("claimer", menu(), claims(), wait(3 SECONDS), then(PROC_REF(finished)))
	op("free", menu(), claims(NONE), wait(3 SECONDS), then(PROC_REF(finished)))
	op("ask", menu(), asks(/datum/prompt/yes_no, fields = list("question" = "Go on?"), ends_on_no = TRUE), then(PROC_REF(finished)))
	op("ask_check", menu(), asks(/datum/prompt/yes_no/tf_check, fields = list("question" = "Sure?")), then(PROC_REF(finished)))
	op("range", ai(), reach(REACH_RANGE(1)), wait(3 SECONDS, keeps = WAIT_KEEPS_DEFAULT & ~STAY), then(PROC_REF(finished)))
	op("worn", menu(), needs(req(PROC_REF(mask_off), because = MSG(tf/masked))), wait(3 SECONDS), then(PROC_REF(finished)))
	op("blocked_body", menu(), claims(CLAIM_BODY), needs(req(PROC_REF(never_ok), because = MSG(tf/masked))), wait(3 SECONDS), then(PROC_REF(finished)))
	op("startw", menu(), needs(req(PROC_REF(under_limit), because = MSG(tf/masked))), starts(PROC_REF(bump_amount)), wait(3 SECONDS), then(PROC_REF(finished)))
	op("cap", menu(), captures(nameof(amount), resume = CANCEL_IF_CHANGED), wait(3 SECONDS), then(PROC_REF(finished)))
	op("sys", ai(), reach(REACH_ANY), wait(3 SECONDS), then(PROC_REF(finished)))

/// A question that is only valid while its machine is not broken: it reads owner_holder().
/datum/prompt/yes_no/tf_check

/datum/prompt/yes_no/tf_check/recheck_extra()
	var/obj/tf_site/S = owner_holder()
	if(!istype(S) || S.amount < 0)
		return "broken"
	return null

/// Requirement: the actor wears no mask (a slot read: the ledger publishes every change of a slot).
/obj/tf_site/proc/mask_off(datum/act/op/A)
	var/mob/M = A.actor
	return !M.get_equipped_item(SLOT_ID_MASK)

/obj/tf_site/proc/never_ok(datum/act/op/A)
	return FALSE

/// Requirement over a tracked var that the op's own start handler writes.
/obj/tf_site/proc/under_limit(datum/act/op/A)
	return amount < 5

/obj/tf_site/proc/bump_amount(datum/act/op/A)
	set_amount(amount + 1)

/obj/tf_site/proc/on_start(datum/act/op/A)
	started++

/obj/tf_site/proc/dyn_text(datum/act/op/A)
	return msg_text("You heft the [name] for [A.actor.name] to see.")

/obj/tf_site/proc/finished(datum/act/op/A)
	done++
	return OP_OK

/obj/tf_site/proc/hold_ended()
	ended++

/// Periodic work on a cadence: counts its steps.
/obj/tf_periodic
	name = "timed forms periodic"
	var/steps = 0

/obj/tf_periodic/periodic_step(delta)
	steps++
	return null

#endif
