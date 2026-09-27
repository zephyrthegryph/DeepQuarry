#define OM_TEST_FLUSH_CHANGE 1

/datum/unit_test/om_derived_flush_owned_lifetime
	needs_test_block = FALSE

/datum/unit_test/om_derived_flush_owned_lifetime/Run()
	var/datum/object_model/test_change_entity/subject = new
	var/datum/observer = new
	var/datum/object_model/derived_watch/watch = om_observe_derived(observer, subject, /datum/object_model/behaviour/test_change_local)
	TEST_ASSERT(watch, "derived observation was installed")
	subject.value = 1
	om_mark_changed(subject, OM_TEST_FLUSH_CHANGE)
	var/datum/object_model/change_state/change_state = subject.om_state.change
	var/datum/object_model/schedule_entry/pending = change_state.om_state?.pending_wakes?[change_state]
	TEST_ASSERT(pending && om_owner(pending) == change_state, "observed refresh is an owned deferred wake")
	subject.value = 2
	om_mark_changed(subject, OM_TEST_FLUSH_CHANGE)
	TEST_ASSERT(change_state.om_state.pending_wakes[change_state] == pending, "multiple writes coalesced into one refresh")
	qdel(subject)
	TEST_ASSERT(QDELETED(pending), "deleting the subject canceled its pending refresh")
	qdel(observer)

#undef OM_TEST_FLUSH_CHANGE
