#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
// An explicit test contract for testing the engine's missing-publication detector.
// The analyzer validates declarations and call sites; runtime additionally requires
// a current fixture and its allocate-tracked target. Production builds expose no form.
#define TEST_FAULT_FIXTURE(T, FIELD) ##T/proc/__test_fault_unpublished_##FIELD() { return TYPE_PROC_REF(T, set_##FIELD) }
#define TEST_FAULT_MISSING_PUBLISH(TARGET, FIELD, VALUE) test_fault_missing_publish(TARGET, #FIELD, VALUE)

/datum/test_publish_fault
	var/field
	var/confirmed = FALSE

/datum/test_publish_fault/proc/confirm_missed_publish(actual_key)
	confirmed = istext(actual_key) && actual_key == field
	return confirmed

/proc/test_fault_missing_publish(datum/target, field, value)
	var/datum/unit_test/fixture = GLOB.current_test
	var/refusal = test_publish_fault_refusal(fixture, target, field)
	if(refusal)
		CRASH(refusal)
	var/datum/test_publish_fault/fault = fixture.allocate(/datum/test_publish_fault)
	fault.field = field
	// Restore through the real setter at normal scope teardown, including failure.
	var/restore_proc = call(target, "__test_fault_unpublished_[field]")()
	fixture.defer_cleanup(target, restore_proc, target.vars[field])
	fixture.defer_cleanup(fixture, TYPE_PROC_REF(/datum/unit_test, verify_publish_fault), fault)
	// Deliberate fault: no setter or changed() call, so the engine audit must find it.
	target.vars[field] = value
	return fault

/datum/unit_test/proc/verify_publish_fault(datum/test_publish_fault/fault)
	if(!fault?.confirmed)
		CRASH("unpublished test fault was not confirmed against actual missed-wake evidence")


/// Pure preflight is directly exercised without injecting an invalid fault.
/proc/test_publish_fault_refusal(datum/unit_test/fixture, datum/target, field)
	if(!fixture || QDELETED(fixture) || fixture != GLOB.current_test || !target || QDELETED(target) || !(target in fixture.allocated))
		return "unpublished test fault needs the current fixture's allocate-tracked target"
	if(!istext(field) || !(field in target.vars) || !hascall(target, "__setter_[field]") || !hascall(target, "__test_fault_unpublished_[field]"))
		return "unpublished test fault needs a declared tracked fixture field"
	return null


#endif
