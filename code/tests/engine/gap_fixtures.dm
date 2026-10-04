// Fixtures of the framework gap closures (OP_DECLINE, ...). Compiled under UNIT_TESTS only; code/modules/unit_tests/dq_gap_tests.dm drives them.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// An op that may decline at run time, with a second op on the same input beneath it.
/obj/gap_decline
	name = "gap decline target"
	var/declines = TRUE
	var/first = 0
	var/second = 0

CAPABILITIES(/obj/gap_decline)
	op("first", item(/obj/item), priority(OP_PRIORITY_TAKE_OUT), then(PROC_REF(ran_first)))
	op("second", item(/obj/item), then(PROC_REF(ran_second)))

/obj/gap_decline/proc/ran_first(datum/act/op/A)
	if(declines)
		return OP_DECLINE
	first++
	return OP_OK

/obj/gap_decline/proc/ran_second(datum/act/op/A)
	second++
	return OP_OK

/// The only op declines: nothing else answers.
/obj/gap_decline_alone
	name = "gap decline alone target"
	var/first = 0

CAPABILITIES(/obj/gap_decline_alone)
	op("first", item(/obj/item), then(PROC_REF(ran_first)))

/obj/gap_decline_alone/proc/ran_first(datum/act/op/A)
	first++
	return OP_DECLINE

/// A type-level every() held by a tracked var: it parks while the var is false and wakes when it is set.
/obj/gap_every
	name = "gap every target"
	var/active = FALSE
	var/ticks = 0

TRACKED(/obj/gap_every, active)

CAPABILITIES(/obj/gap_every)
	every(1 SECOND, then(PROC_REF(tick)), when = nameof(active))

/obj/gap_every/proc/tick(datum/act/timer/A)
	ticks++

/// The same, running from creation.
/obj/gap_every/running
	active = TRUE

/// A gate that is a proc (its reads may be incomplete): the every() keeps polling instead of parking.
/obj/gap_every_proc
	name = "gap every proc target"
	var/on = FALSE
	var/ticks = 0

TRACKED(/obj/gap_every_proc, on)

CAPABILITIES(/obj/gap_every_proc)
	every(1 SECOND, then(PROC_REF(tick)), when = PROC_REF(is_on))

/obj/gap_every_proc/proc/is_on(datum/act/A)
	return on

/obj/gap_every_proc/proc/tick(datum/act/timer/A)
	ticks++

#endif
