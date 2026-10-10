// Fixtures of the storage conversion's engine pieces (passes() in a click, the ledger read inside a condition). Compiled under UNIT_TESTS only;
// code/modules/unit_tests/dq_p2_storage_engine_tests.dm drives them.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A target with two ops on one input: the first passes, so the second answers after it.
/obj/p2s_chain
	name = "p2 chain target"
	var/first = 0
	var/second = 0

CAPABILITIES(/obj/p2s_chain)
	op("first", item(/obj/item), priority(OP_PRIORITY_TAKE_OUT), then(PROC_REF(ran_first)), passes())
	op("second", item(/obj/item), then(PROC_REF(ran_second)))

/obj/p2s_chain/proc/ran_first(datum/act/op/A)
	first++
	return OP_OK

/obj/p2s_chain/proc/ran_second(datum/act/op/A)
	second++
	return OP_OK

/// The same two ops, the first not passing: it answers alone.
/obj/p2s_chain_stop
	name = "p2 chain stop target"
	var/first = 0
	var/second = 0

CAPABILITIES(/obj/p2s_chain_stop)
	op("first", item(/obj/item), priority(OP_PRIORITY_TAKE_OUT), then(PROC_REF(ran_first)))
	op("second", item(/obj/item), then(PROC_REF(ran_second)))

/obj/p2s_chain_stop/proc/ran_first(datum/act/op/A)
	first++
	return OP_OK

/obj/p2s_chain_stop/proc/ran_second(datum/act/op/A)
	second++
	return OP_OK

MSG_DEF_SELF(p2s/never, "Never.")

/// The first passes but its requirement refuses: nothing ran, so nothing passes.
/obj/p2s_chain_refused
	name = "p2 chain refused target"
	var/first = 0
	var/second = 0

CAPABILITIES(/obj/p2s_chain_refused)
	op("first", item(/obj/item), priority(OP_PRIORITY_TAKE_OUT), needs(req_bool(PROC_REF(never), because = MSG(p2s/never))), then(PROC_REF(ran_first)), passes())
	op("second", item(/obj/item), then(PROC_REF(ran_second)))

/obj/p2s_chain_refused/proc/never(datum/act/op/A)
	return FALSE

/obj/p2s_chain_refused/proc/ran_first(datum/act/op/A)
	first++
	return OP_OK

/obj/p2s_chain_refused/proc/ran_second(datum/act/op/A)
	second++
	return OP_OK

#endif
