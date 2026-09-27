#define OM_TEST_CHANGED_VALUE 1

/datum/object_model/test_change_entity
	var/value = 0
	var/computes = 0
	var/notifications = 0
	var/owned_runs = 0
	var/related_runs = 0

/datum/object_model/test_change_entity/om_declare(datum/object_model/archetype/A)
	..()
	A.track_changes(OM_TEST_CHANGED_VALUE)
	A.add(/datum/object_model/behaviour/test_change_local)
	A.add(/datum/object_model/behaviour/test_change_owned)
	A.add(/datum/object_model/behaviour/test_change_related)
	A.add(/datum/object_model/behaviour/test_scheduled_owned)
	A.add(/datum/object_model/behaviour/test_scheduled_related)
	A.slot("parts", /datum/object_model/test_change_entity, 5, OM_SLOT_DELETE)
	A.relation(/datum/object_model/relation/test_change_link)

/datum/object_model/relation/test_change_link
	from_type = /datum/object_model/test_change_entity
	to_type = /datum/object_model/test_change_entity
	shape = OM_REL_MANY_TO_MANY

/datum/object_model/relation/test_owned_change
	from_type = /datum/object_model/test_change_entity
	to_type = /datum/object_model/test_change_entity
	source_single = TRUE
	ownership = OM_REL_OWN_SOURCE

/datum/object_model/behaviour/test_change_local
	derived_input_mask = OM_TEST_CHANGED_VALUE

/datum/object_model/behaviour/test_change_local/compute_derived(datum/source, list/config)
	var/datum/object_model/test_change_entity/E = source
	E.computes++
	return E.value % 2

/datum/object_model/behaviour/test_change_local/on_derived_changed(datum/source, old_value, new_value, list/config)
	var/datum/object_model/test_change_entity/E = source
	E.notifications++

/datum/object_model/behaviour/test_change_owned
	derived_owned_inputs = list(list("parts", OM_TEST_CHANGED_VALUE))

/datum/object_model/behaviour/test_change_owned/compute_derived(datum/source, list/config)
	var/result = 0
	for(var/datum/object_model/test_change_entity/part as anything in om_children(source, "parts"))
		result += part.value
	return result

/datum/object_model/behaviour/test_change_related
	derived_relation_inputs = list(list(/datum/object_model/relation/test_change_link, OM_READ_INCOMING, OM_TEST_CHANGED_VALUE))

/datum/object_model/behaviour/test_change_related/compute_derived(datum/source, list/config)
	var/result = 0
	for(var/datum/object_model/test_change_entity/related as anything in om_linked_to(source, /datum/object_model/relation/test_change_link))
		result += related.value
	return result

/datum/object_model/behaviour/test_scheduled_owned
	run_owned_inputs = list(list("parts", OM_TEST_CHANGED_VALUE))

/datum/object_model/behaviour/test_scheduled_owned/on_run(datum/source, seconds, list/config)
	var/datum/object_model/test_change_entity/E = source
	E.owned_runs++
	return 0

/datum/object_model/behaviour/test_scheduled_related
	run_relation_inputs = list(list(/datum/object_model/relation/test_change_link, OM_READ_INCOMING, OM_TEST_CHANGED_VALUE))

/datum/object_model/behaviour/test_scheduled_related/on_run(datum/source, seconds, list/config)
	var/datum/object_model/test_change_entity/E = source
	E.related_runs++
	return 0

/datum/unit_test/om_change_tracking
	needs_test_block = FALSE

/datum/unit_test/om_change_tracking/Run()
	var/datum/object_model/test_change_entity/E = new
	TEST_ASSERT_NULL(E.om_state, "untouched entity has no model state")
	TEST_ASSERT_EQUAL(om_track_change(E, OM_TEST_CHANGED_VALUE), 0, "revision starts on demand")
	TEST_ASSERT_EQUAL(om_revision(E), 0, "task revision starts on demand")
	TEST_ASSERT_EQUAL(om_derived_read(E, /datum/object_model/behaviour/test_change_local), 0, "initial derived read")
	TEST_ASSERT_EQUAL(E.computes, 1, "computed once")
	E.value = 2
	om_mark_changed(E, OM_TEST_CHANGED_VALUE)
	TEST_ASSERT_EQUAL(om_change_revision(E, OM_TEST_CHANGED_VALUE), 1, "tracked revision advances")
	TEST_ASSERT_EQUAL(om_revision(E), 1, "tracked mutation invalidates task stamp")
	TEST_ASSERT_EQUAL(om_derived_read(E, /datum/object_model/behaviour/test_change_local), 0, "fresh read after same effective result")
	TEST_ASSERT_EQUAL(E.computes, 2, "one refresh after write")
	var/datum/object_model/derived_watch/W = om_observe_derived(E, E, /datum/object_model/behaviour/test_change_local)
	TEST_ASSERT_NOTNULL(W, "derived observation starts")
	E.value = 4
	om_mark_changed(E, OM_TEST_CHANGED_VALUE)
	TEST_ASSERT_EQUAL(om_derived_read(E, /datum/object_model/behaviour/test_change_local), 0, "same effective result is fresh")
	TEST_ASSERT_EQUAL(E.notifications, 0, "unchanged effective result has no event")
	E.value = 5
	om_mark_changed(E, OM_TEST_CHANGED_VALUE)
	TEST_ASSERT_EQUAL(om_derived_read(E, /datum/object_model/behaviour/test_change_local), 1, "new effective result")
	TEST_ASSERT_EQUAL(E.notifications, 1, "observed effective change fires once")
	qdel(E)

/datum/unit_test/om_change_related_inputs
	needs_test_block = FALSE

/datum/unit_test/om_change_related_inputs/Run()
	var/datum/object_model/test_change_entity/owner = new
	var/datum/object_model/test_change_entity/part = new
	var/datum/object_model/behaviour_runtime/R = om_behaviour_start(owner)
	R.run_ready()
	TEST_ASSERT_EQUAL(owner.owned_runs, 1, "Owned scheduled behaviour starts once")
	TEST_ASSERT_EQUAL(owner.related_runs, 1, "Related scheduled behaviour starts once")
	TEST_ASSERT_EQUAL(om_derived_read(owner, /datum/object_model/behaviour/test_change_owned), 0, "empty ownership fold")
	TEST_ASSERT(om_claim(owner, "parts", part), "part attached")
	R.run_ready()
	TEST_ASSERT_EQUAL(owner.owned_runs, 2, "Owned membership wakes only the dependent behaviour")
	TEST_ASSERT_EQUAL(owner.related_runs, 1, "Owned membership leaves unrelated behaviour asleep")
	TEST_ASSERT_EQUAL(om_derived_read(owner, /datum/object_model/behaviour/test_change_owned), 0, "membership refresh")
	part.value = 7
	om_mark_changed(part, OM_TEST_CHANGED_VALUE)
	R.run_ready()
	TEST_ASSERT_EQUAL(owner.owned_runs, 3, "Child tracked change wakes owner behaviour")
	TEST_ASSERT_EQUAL(om_derived_read(owner, /datum/object_model/behaviour/test_change_owned), 7, "child write invalidates owner")
	TEST_ASSERT(om_release(part), "part detached")
	TEST_ASSERT_EQUAL(om_derived_read(owner, /datum/object_model/behaviour/test_change_owned), 0, "detach refreshes owner")
	var/datum/object_model/test_change_entity/source = new
	TEST_ASSERT_EQUAL(om_derived_read(owner, /datum/object_model/behaviour/test_change_related), 0, "empty inverse relation")
	TEST_ASSERT(om_link(source, /datum/object_model/relation/test_change_link, owner), "relation attached")
	R.run_ready()
	TEST_ASSERT_EQUAL(owner.related_runs, 2, "Related membership wakes target behaviour")
	source.value = 9
	om_mark_changed(source, OM_TEST_CHANGED_VALUE)
	R.run_ready()
	TEST_ASSERT_EQUAL(owner.related_runs, 3, "Related tracked change wakes target behaviour")
	TEST_ASSERT_EQUAL(om_derived_read(owner, /datum/object_model/behaviour/test_change_related), 9, "related write invalidates target")
	TEST_ASSERT(om_unlink(source, /datum/object_model/relation/test_change_link, owner), "relation removed")
	TEST_ASSERT_EQUAL(om_derived_read(owner, /datum/object_model/behaviour/test_change_related), 0, "relation rebinds")
	qdel(owner)
	qdel(part)
	qdel(source)

/datum/unit_test/om_owned_relation
	needs_test_block = FALSE

/datum/unit_test/om_owned_relation/Run()
	var/datum/object_model/test_change_entity/first_body = new
	var/datum/object_model/test_change_entity/second_body = new
	var/datum/object_model/test_change_entity/wound = new
	var/kind = /datum/object_model/relation/test_owned_change
	TEST_ASSERT(om_link(wound, kind, first_body), "wound links to first body")
	TEST_ASSERT_EQUAL(om_owner(wound), first_body, "relation is lifetime authority")
	TEST_ASSERT(om_link(wound, kind, second_body), "wound transfers to second body")
	TEST_ASSERT(!om_has_link(wound, kind, first_body), "old body link removed")
	TEST_ASSERT_EQUAL(om_owner(wound), second_body, "ownership transfers with relation")
	qdel(first_body)
	TEST_ASSERT(!QDELETED(wound), "old body destruction does not delete transferred wound")
	qdel(second_body)
	TEST_ASSERT(QDELETED(wound), "owning body destroys wound")

/datum/unit_test/om_physical_relation
	needs_test_block = FALSE

/datum/unit_test/om_physical_relation/Run()
	var/obj/holder = new
	var/obj/thing = new
	var/kind = /datum/object_model/relation/physical_contents
	TEST_ASSERT_EQUAL(om_revision(holder), 0, "physical holder can be watched lazily")
	TEST_ASSERT(thing.forceMove(holder), "physical insertion succeeded")
	TEST_ASSERT(om_has_link(holder, kind, thing), "loc creates virtual relation")
	TEST_ASSERT(thing in om_linked(holder, kind), "forward query reads contents")
	TEST_ASSERT(holder in om_linked_to(thing, kind), "inverse query reads loc")
	TEST_ASSERT_EQUAL(om_revision(holder), 1, "movement advances watched holder revision")
	TEST_ASSERT(thing.moveToNullspace(), "physical removal succeeded")
	TEST_ASSERT(!om_has_link(holder, kind, thing), "virtual relation follows loc removal")
	TEST_ASSERT_EQUAL(om_revision(holder), 2, "removal advances watched holder revision")
	qdel(thing)
	qdel(holder)

/datum/object_model/test_slot_listener
	var/hits = 0
	var/contributions = 0
	var/last_slot
	var/last_inserted

/datum/object_model/test_slot_listener/proc/on_slot_event(datum/source, datum/object_model/event/E, atom/movable/member, slot_id, inserted, d)
	hits++
	last_slot = slot_id
	last_inserted = inserted

/datum/object_model/test_slot_listener/proc/on_contribution_event(datum/source, datum/object_model/event/E, atom/movable/member, slot_id, c, d)
	contributions++
	last_slot = slot_id

/datum/object_model/subscription_rule/test_slot_membership
	event_path = /datum/object_model/event/slot_membership_changed
	handler = TYPE_PROC_REF(/datum/object_model/test_slot_listener, on_slot_event)

/datum/object_model/subscription_rule/test_slot_contribution
	event_path = /datum/object_model/event/slot_contribution_changed
	handler = TYPE_PROC_REF(/datum/object_model/test_slot_listener, on_contribution_event)

/datum/unit_test/om_slot_relation
	needs_test_block = FALSE

/datum/unit_test/om_slot_relation/Run()
	var/obj/item/dq_containment_box/holder = new
	var/obj/item/dq_containment_test/wood/thing = new
	var/datum/ledger/L = dq_ledger(holder)
	var/datum/object_model/test_slot_listener/listener = new
	var/datum/object_model/subscription/S = om_subscribe(listener, /datum/object_model/subscription_rule/test_slot_membership, holder)
	var/kind = /datum/object_model/relation/slot_member
	TEST_ASSERT(S, "slot observer subscribes")
	TEST_ASSERT_EQUAL(om_revision(holder), 0, "holder starts at revision zero")
	TEST_ASSERT(thing.forceMove(holder), "slot insertion succeeded")
	TEST_ASSERT(om_has_link(holder, kind, thing), "ledger creates virtual slot relation")
	TEST_ASSERT(thing in om_linked(holder, kind), "slot forward query reads ledger")
	TEST_ASSERT(holder in om_linked_to(thing, kind), "slot inverse query reads ledger")
	TEST_ASSERT_EQUAL(om_revision(holder), 1, "insertion advances holder revision once")
	TEST_ASSERT_EQUAL(listener.hits, 1, "observer receives insertion")
	TEST_ASSERT(listener.last_inserted, "observer sees inserted state")
	L.reslot(thing, "main")
	TEST_ASSERT_EQUAL(L.entries[thing][LEDGER_E_SLOT], "main", "reslot succeeds")
	TEST_ASSERT(om_has_link(holder, kind, thing), "reslot preserves relation")
	TEST_ASSERT_EQUAL(listener.last_slot, "main", "observer receives destination slot")
	TEST_ASSERT(thing.moveToNullspace(), "slot removal succeeded")
	TEST_ASSERT(!om_has_link(holder, kind, thing), "slot relation follows removal")
	TEST_ASSERT(!listener.last_inserted, "observer receives removal")
	qdel(S)
	qdel(listener)
	qdel(thing)
	qdel(holder)

/obj/item/dq_containment_test/wood/om_slot_test_member
	var/score = 0

/obj/item/dq_containment_test/wood/om_slot_test_member/om_declare(datum/object_model/archetype/A)
	..()
	A.track_changes(OM_TEST_CHANGED_VALUE)

/obj/item/dq_containment_box/om_slot_test_holder

/obj/item/dq_containment_box/om_slot_test_holder/om_declare(datum/object_model/archetype/A)
	..()
	A.relation(/datum/object_model/relation/slot_member)
	A.add(/datum/object_model/behaviour/test_slot_sum)

/datum/object_model/behaviour/test_slot_sum
	derived_relation_inputs = list(list(/datum/object_model/relation/slot_member, OM_READ_OUTGOING, OM_TEST_CHANGED_VALUE))

/datum/object_model/behaviour/test_slot_sum/compute_derived(datum/source, list/config)
	var/result = 0
	for(var/obj/item/dq_containment_test/wood/om_slot_test_member/member as anything in om_linked(source, /datum/object_model/relation/slot_member))
		result += member.score
	return result

/datum/unit_test/om_slot_derived_inputs
	needs_test_block = FALSE

/datum/unit_test/om_slot_derived_inputs/Run()
	var/obj/item/dq_containment_box/om_slot_test_holder/holder = new
	var/obj/item/dq_containment_test/wood/om_slot_test_member/member = new
	var/datum/object_model/test_slot_listener/listener = new
	var/datum/object_model/subscription/S = om_subscribe(listener, /datum/object_model/subscription_rule/test_slot_contribution, holder)
	TEST_ASSERT(S, "contribution observer subscribes")
	TEST_ASSERT_EQUAL(om_derived_read(holder, /datum/object_model/behaviour/test_slot_sum), 0, "empty slot sum")
	TEST_ASSERT(member.forceMove(holder), "member enters holder")
	TEST_ASSERT_EQUAL(member.loc, holder, "member loc is holder")
	TEST_ASSERT(holder.ledger?.entries?[member], "holder ledger indexes member")
	TEST_ASSERT(om_has_link(holder, /datum/object_model/relation/slot_member, member), "member is in virtual slot relation")
	member.score = 3
	om_mark_changed(member, OM_TEST_CHANGED_VALUE)
	TEST_ASSERT_EQUAL(om_derived_read(holder, /datum/object_model/behaviour/test_slot_sum), 3, "child write refreshes holder")
	member.score = 5
	om_mark_changed(member, OM_TEST_CHANGED_VALUE)
	TEST_ASSERT_EQUAL(om_derived_read(holder, /datum/object_model/behaviour/test_slot_sum), 5, "second write refreshes holder")
	member.score = 8
	holder.ledger.refresh(member)
	TEST_ASSERT_EQUAL(om_derived_read(holder, /datum/object_model/behaviour/test_slot_sum), 8, "explicit contribution refresh invalidates derived view")
	TEST_ASSERT_EQUAL(listener.contributions, 1, "explicit refresh emits one contribution event")
	TEST_ASSERT(member.moveToNullspace(), "member leaves holder")
	TEST_ASSERT_EQUAL(om_derived_read(holder, /datum/object_model/behaviour/test_slot_sum), 0, "removal refreshes holder")
	qdel(S)
	qdel(listener)
	qdel(member)
	qdel(holder)

#undef OM_TEST_CHANGED_VALUE
