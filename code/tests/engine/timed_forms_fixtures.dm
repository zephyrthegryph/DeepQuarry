// Fixtures of the timed-action forms: starts(), plays(at_start), msg_text(), asks(ends_on_no), captures() on a wait, claims(), ORIGIN_SYSTEM pendings,
// hold_busy() and every_running(). Compiled under UNIT_TESTS only; code/modules/unit_tests/dq_timed_forms_tests.dm drives them.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

MSG_DEF_SELF(tf/begins, "You begin the long work.")

/obj/tf_site
	name = "timed forms site"
	var/started = 0
	var/done = 0
	var/ended = 0
	var/amount = 1

CAPABILITIES(/obj/tf_site)
	op("start", menu(), begins(MSG(tf/begins)), starts(PROC_REF(on_start)), wait(3 SECONDS), then(PROC_REF(finished)))
	op("dyn", menu(), begins(PROC_REF(dyn_text)), wait(1 SECOND), then(PROC_REF(finished)))
	op("claimer", menu(), claims(), wait(3 SECONDS), then(PROC_REF(finished)))
	op("free", menu(), claims(NONE), wait(3 SECONDS), then(PROC_REF(finished)))
	op("ask", menu(), asks(/datum/prompt/yes_no, fields = list("question" = "Go on?"), ends_on_no = TRUE), then(PROC_REF(finished)))
	op("cap", menu(), captures(nameof(amount), resume = CANCEL_IF_CHANGED), wait(3 SECONDS), then(PROC_REF(finished)))
	op("sys", ai(), reach(REACH_ANY), wait(3 SECONDS), then(PROC_REF(finished)))

/obj/tf_site/proc/on_start(datum/act/op/A)
	started++

/obj/tf_site/proc/dyn_text(datum/act/op/A)
	return msg_text("You heft the [name] for [A.actor.name] to see.")

/obj/tf_site/proc/finished(datum/act/op/A)
	done++
	return OP_OK

/obj/tf_site/proc/hold_ended()
	ended++

#endif
