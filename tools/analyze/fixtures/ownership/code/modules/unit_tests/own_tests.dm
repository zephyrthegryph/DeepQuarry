// Exempt path: unit tests build the forbidden things on purpose. Only the usage-driven checks read it.
/obj/holder/proc/test_everything(X)
	held = null
	stuff += src
	var/datum/callback/cb = CALLBACK(src, PROC_REF(test_everything))
	var/h = om_handle(src)
	DECLARE_REF(thing)
	own_set(src, "held", src)
	own_set(src, "ghost_in_tests", src)
	own_set(X, nameof(ghost_in_tests_two), src)
	rel_set(src, nameof(unit_test_contra), src)

/obj/holder/proc/test_contra_own()
	own_set(src, nameof(unit_test_contra), src)

/obj/holder
	var/obj/item/unit_test_contra
	var/test_handle
