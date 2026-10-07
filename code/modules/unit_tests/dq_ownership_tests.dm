// Ownership framework (doc/rewrite/ownership.md): own, shared, proto, relations, identity.

/datum/own_test_holder
	var/datum/own_test_child/child
	var/list/children
	var/list/values
	var/datum/own_test_partner/partner
	var/list/members
	var/list/peers
	var/datum/own_test_child/view
	var/datum/species/species
	var/released = 0

CAPABILITIES(/datum/own_test_holder)
	owns_one(nameof(child))
	owns_many(nameof(children))
	owns_many(nameof(values))

/datum/own_test_holder/ownership()
	. = ..()
	. += rel_one(nameof(species), kind = RELK_OWNED, policy = OWN_PRIVATE_COPY)

/datum/own_test_holder/relations()
	. = ..()
	. += rel_one(nameof(partner), back = nameof(/datum/own_test_partner::holder))
	. += rel_many(nameof(members), back = nameof(/datum/own_test_member::group))
	. += rel_many(nameof(peers), back = nameof(/datum/own_test_holder::peers))
/datum/own_test_partner/relations()
	. = ..()
	. += rel_one(nameof(holder), back = nameof(/datum/own_test_holder::partner))
/datum/own_test_member/relations()
	. = ..()
	. += rel_one(nameof(group), back = nameof(/datum/own_test_holder::members))

/datum/own_test_holder/on_owned_release(var_name, datum/child)
	. = ..()
	released++

/datum/own_test_child
	var/label = "child"
	var/datum/own_test_child/grandchild

CAPABILITIES(/datum/own_test_child)
	owns_one(nameof(grandchild))

/datum/own_test_partner
	var/datum/own_test_holder/holder

/datum/own_test_member
	var/datum/own_test_holder/group

/obj/own_test_keyed_source
	var/key = "k1"
	var/obj/own_test_keyed_target/target

/obj/own_test_keyed_source/relations()
	. = ..()
	. += rel_one(nameof(target), keyed = nameof(key), keyed_target = /obj/own_test_keyed_target)

/obj/own_test_keyed_target
	var/id = "k1"

/obj/own_test_keyed_target/relations()
	. = ..()
	. += rel_key(nameof(id))

/datum/unit_test/ownership_own_accessors

/datum/unit_test/ownership_own_accessors/Run()
	var/list/capture = list()
	set_global("dq_lifecycle_report_capture", capture)
	var/datum/own_test_holder/H = new
	var/datum/own_test_child/A = new
	rel_set(H, nameof(H.child), A)
	TEST_ASSERT_EQUAL(H.child, A, "rel_set writes the var")
	TEST_ASSERT_EQUAL(owner_of(A), H, "the owner is stamped on the child")
	TEST_ASSERT_EQUAL(owner_slot_of(A), "child", "the owner's var is stamped on the child")
	var/datum/own_test_child/B = new
	rel_set(H, nameof(H.child), B)
	TEST_ASSERT(QDELETED(A), "rel_set destroys the value it replaces (DELETE policy)")
	TEST_ASSERT(H.released >= 1, "the owned-child release hook ran")
	var/datum/own_test_child/taken = rel_take(H, nameof(H.child))
	TEST_ASSERT_EQUAL(taken, B, "own_take returns the value")
	TEST_ASSERT(isnull(H.child) && isnull(owner_of(B)), "own_take detaches and unstamps")
	rel_add(H, nameof(H.children), B)
	rel_add(H, nameof(H.values), new /datum/own_test_child, "a")
	TEST_ASSERT(B in H.children, "rel_add adds to the owned list")
	var/datum/own_test_holder/H2 = new
	rel_move(H, nameof(H.children), H2, nameof(H2.child), B)
	TEST_ASSERT_EQUAL(H2.child, B, "own_transfer moves a list member into another owner's var")
	TEST_ASSERT_EQUAL(owner_of(B), H2, "the move restamps the owner")
	TEST_ASSERT(!length(H.children), "the source list no longer holds it")
	TEST_ASSERT(!length(capture), "no reports for legal moves: [json_encode(capture)]")
	// Double ownership is refused.
	rel_set(H, nameof(H.child), B)
	TEST_ASSERT(length(capture) == 1 && findtext(capture[1], "already owned"), "adopting a value another holder owns is reported: [json_encode(capture)]")
	TEST_ASSERT_EQUAL(owner_of(B), H2, "the refused adoption leaves the owner alone")
	capture.Cut()
	// own_move finds the current owner itself.
	own_move(B, H, nameof(H.child))
	TEST_ASSERT(H.child == B && isnull(H2.child), "own_move transfers from whatever owns it")
	var/datum/own_test_child/V = H.values["a"]
	qdel(H)
	TEST_ASSERT(QDELETED(B) && QDELETED(V), "destroying the owner deletes its owned values")
	qdel(H2)
	set_global("dq_lifecycle_report_capture", null)
	TEST_ASSERT(!length(capture), "no reports: [json_encode(capture)]")

/datum/unit_test/ownership_phase8_reset

/datum/unit_test/ownership_phase8_reset/Run()
	var/list/capture = list()
	set_global("dq_lifecycle_report_capture", capture)
	var/datum/own_test_holder/H = new
	rel_set(H, nameof(H.child), new /datum/own_test_child)
	dq_lifecycle_clear_links(H) // phase 4
	var/datum/own_test_child/late = new
	H.child = late
	own_scrub(H) // phase 8
	set_global("dq_lifecycle_report_capture", null)
	TEST_ASSERT(QDELETED(late), "phase 8 deletes a value re-set during teardown")
	TEST_ASSERT(length(capture) && findtext(capture[1], "re-set during teardown"), "and reports it: [json_encode(capture)]")
	qdel(H)

/datum/unit_test/ownership_orphan_audit

/datum/unit_test/ownership_orphan_audit/Run()
	var/datum/own_test_holder/H = new
	var/datum/own_test_child/A = new
	rel_set(H, nameof(H.child), A)
	H.child = null
	var/list/lines = own_audit(quiet = TRUE)
	var/found = FALSE
	for(var/line in lines)
		if(findtext(line, "orphan") && findtext(line, "/datum/own_test_child"))
			found = TRUE
	TEST_ASSERT(found, "the audit finds a value dropped without own_take/rel_set: [json_encode(lines)]")
	qdel(A)
	qdel(H)

/datum/unit_test/ownership_relation_views

/datum/unit_test/ownership_relation_views/Run()
	var/list/capture = list()
	set_global("dq_lifecycle_report_capture", capture)
	var/datum/own_test_holder/H = new
	var/datum/own_test_child/T = new
	rel_set(H, nameof(H.view), T)
	TEST_ASSERT_EQUAL(H.view, T, "rel_set writes the view")
	qdel(T)
	TEST_ASSERT(isnull(H.view), "the target's death clears the view")
	// Pairs set both sides; exclusivity unlinks the old partner.
	var/datum/own_test_partner/P1 = new
	var/datum/own_test_partner/P2 = new
	rel_set(H, nameof(H.partner), P1)
	TEST_ASSERT_EQUAL(P1.holder, H, "a pair sets the partner's side")
	rel_set(P2, nameof(P2.holder), H)
	TEST_ASSERT(H.partner == P2 && isnull(P1.holder), "linking a new partner unlinks the old one on both sides")
	// 1:N pairs.
	var/datum/own_test_member/M1 = new
	var/datum/own_test_member/M2 = new
	rel_set(M1, nameof(M1.group), H)
	rel_add(H, nameof(H.members), M2)
	TEST_ASSERT((M1 in H.members) && M2.group == H, "either side of a 1:N pair links both")
	qdel(M1)
	TEST_ASSERT(!(M1 in H.members), "a member's death leaves the list")
	// Symmetric membership.
	var/datum/own_test_holder/Q = new
	rel_add(H, nameof(H.peers), Q)
	TEST_ASSERT((Q in H.peers) && (H in Q.peers), "REL_SET links both ends")
	// The source's death clears its partners' sides.
	qdel(H)
	TEST_ASSERT(isnull(P2.holder) && isnull(M2.group) && !(H in Q.peers), "the source's death clears every partner side")
	TEST_ASSERT(!length(P2.om_refs_in) && !length(Q.om_refs_in), "and every reverse index entry")
	// Linking to a dying entity is refused.
	var/datum/own_test_holder/H3 = new
	var/datum/own_test_child/dying = new
	dying.gc_destroyed = GC_CURRENTLY_BEING_QDELETED
	rel_set(H3, nameof(H3.view), dying)
	dying.gc_destroyed = null
	TEST_ASSERT(isnull(H3.view), "a link to an entity being destroyed is refused")
	set_global("dq_lifecycle_report_capture", null)
	qdel(dying)
	qdel(H3)
	qdel(P1)
	qdel(P2)
	qdel(M2)
	qdel(Q)

/datum/unit_test/ownership_turf_views_z_release

/datum/unit_test/ownership_turf_views_z_release/Run()
	var/datum/own_test_holder/H = new
	var/turf/T = run_loc_floor_bottom_left
	rel_set(H, nameof(H.view), T)
	TEST_ASSERT_EQUAL(H.view, T, "a turf can be a relation target")
	var/list/by_turf = GLOB.rel_turf_index["[T.z]"]
	TEST_ASSERT(by_turf && by_turf[own_key(T)], "a view naming a turf is indexed under its z-level")
	rel_clear(H, nameof(H.view))
	var/list/index = by_turf ? by_turf[own_key(T)] : null
	TEST_ASSERT(!index || !index[own_key(H)], "clearing the view leaves the turf index")
	// Releasing a z-level clears every view naming its turfs. The test map's own z-level holds the
	// harness's views too, so the release is exercised on a private key with this turf's entry.
	rel_set(H, nameof(H.view), T)
	var/list/entry = by_turf[own_key(T)]
	var/fake_z = 90000 + T.z
	GLOB.rel_turf_index["[fake_z]"] = list("[own_key(T)]" = list("[own_key(H)]" = "view"))
	entry -= own_key(H)
	var/cleared = rel_drop_z(fake_z)
	TEST_ASSERT(isnull(H.view) && cleared == 1, "releasing the z-level clears views naming its turfs ([cleared])")
	// A turf handle carries the z-level's generation.
	var/h = om_handle(T)
	TEST_ASSERT_EQUAL(om_resolve(h), T, "a turf handle resolves on a live z-level")
	om_z_generation_bump(T.z)
	TEST_ASSERT(isnull(om_resolve(h)), "a turf handle stops resolving once its z-level generation moves on")
	GLOB.om_z_generations[T.z]-- // the test map's z-level was not really released
	TEST_ASSERT_EQUAL(om_resolve(h), T, "and resolves again once the generation is back")
	qdel(H)

/datum/unit_test/ownership_proto

/datum/unit_test/ownership_proto/Run()
	var/datum/own_test_holder/H = new
	var/datum/species/proto = GLOB.all_species[SPECIES_HUMAN]
	proto_set(H, nameof(H.species), proto)
	TEST_ASSERT(!rel_is_private(H, nameof(H.species)), "a registered prototype is shared")
	var/datum/species/mine = rel_private(H, nameof(H.species))
	TEST_ASSERT(mine != proto && rel_is_private(H, nameof(H.species)), "proto_private makes an owned private copy")
	TEST_ASSERT(rel_private(H, nameof(H.species)) == mine, "and returns the same copy afterwards")
	proto_set(H, nameof(H.species), proto)
	TEST_ASSERT(QDELETED(mine), "proto_set deletes the private copy it replaces")
	var/datum/species/second = rel_private(H, nameof(H.species))
	qdel(H)
	TEST_ASSERT(QDELETED(second) && !QDELETED(proto), "teardown deletes private copies only")

/datum/unit_test/ownership_registry

/datum/unit_test/ownership_registry/Run()
	var/datum/species/S = GLOB.all_species[SPECIES_HUMAN]
	TEST_ASSERT(is_registered(S), "a registered species is a registry instance")
	var/datum/species/copy = new S.type
	TEST_ASSERT(!is_registered(copy), "a copy of a registry type is not registered")
	qdel(S)
	TEST_ASSERT(!QDELETED(S), "a registered instance refuses an unforced qdel()")
	var/list/capture = list()
	set_global("dq_lifecycle_report_capture", capture)
	var/datum/own_test_holder/H = new
	shared_set(H, nameof(H.view), copy)
	set_global("dq_lifecycle_report_capture", null)
	TEST_ASSERT(length(capture) && findtext(capture[1], "not a registered instance"), "shared_set refuses an unregistered value: [json_encode(capture)]")
	H.view = null
	qdel(copy)
	qdel(H)

/datum/unit_test/ownership_entity_clone

/datum/unit_test/ownership_entity_clone/Run()
	var/datum/own_test_holder/H = new
	var/datum/own_test_child/A = new
	A.label = "original"
	rel_set(A, nameof(A.grandchild), new /datum/own_test_child)
	rel_set(H, nameof(H.child), A)
	var/datum/own_test_holder/H2 = new
	var/datum/own_test_child/C = entity_clone(A, H2, "child")
	TEST_ASSERT(C && C != A, "entity_clone makes a new entity")
	TEST_ASSERT_EQUAL(C.label, "original", "with the saved state")
	TEST_ASSERT(C.grandchild && C.grandchild != A.grandchild, "and its own copies of owned children")
	TEST_ASSERT_EQUAL(owner_of(C), H2, "adopted into the new owner")
	TEST_ASSERT_EQUAL(owner_of(C.grandchild), C, "its children owned by the clone")
	qdel(H)
	qdel(H2)

/datum/unit_test/ownership_deep_capture

/datum/unit_test/ownership_deep_capture/Run()
	var/datum/own_test_child/A = new
	var/list/capture = capture_args(list(list("nested" = list(A)), 3))
	TEST_ASSERT(capture, "a nested datum is captured")
	var/list/captured = capture[1]
	TEST_ASSERT(!findtext(json_encode(captured), "\[0x"), "no reference survives in the capture")
	var/list/copy = captured.Copy()
	TEST_ASSERT(resolve_captured(copy, capture[2]), "it resolves while the datum lives")
	var/list/outer = copy[1]
	var/list/inner = outer["nested"]
	TEST_ASSERT_EQUAL(inner[1], A, "back to the datum")
	qdel(A)
	copy = captured.Copy()
	TEST_ASSERT(!resolve_captured(copy, capture[2]), "and refuses once it is gone")
	var/list/reports = list()
	set_global("dq_lifecycle_report_capture", reports)
	var/datum/own_test_child/K = new
	var/list/keyed = list()
	keyed[K] = 1
	TEST_ASSERT(isnull(capture_args(list(keyed))), "a datum used as an assoc key is refused")
	set_global("dq_lifecycle_report_capture", null)
	qdel(K)
	var/datum/own_test_child/B = new
	var/list/spec = om_callable(B, TYPE_PROC_REF(/datum/own_test_child, test_label), "x")
	TEST_ASSERT_EQUAL(om_run(spec, "y"), "childxy", "om_run runs a callable with stored and extra args")
	qdel(B)
	TEST_ASSERT(isnull(om_run(spec, "y")), "a callable whose target is gone is dropped")

/datum/own_test_child/proc/test_label(a, b)
	return "[label][a][b]"

/datum/unit_test/ownership_keyed_links

/datum/unit_test/ownership_keyed_links/Run()
	var/obj/own_test_keyed_source/S = allocate(/obj/own_test_keyed_source)
	TEST_ASSERT(isnull(S.target), "no target yet")
	var/obj/own_test_keyed_target/T = allocate(/obj/own_test_keyed_target)
	TEST_ASSERT_EQUAL(S.target, T, "a target materializing with a matching key links the waiting source")
	qdel(T)
	TEST_ASSERT(isnull(S.target), "and its death clears the view")
	var/obj/own_test_keyed_target/T2 = allocate(/obj/own_test_keyed_target)
	var/obj/own_test_keyed_source/S2 = allocate(/obj/own_test_keyed_source)
	TEST_ASSERT_EQUAL(S2.target, T2, "a source materializing after its target links at once")

/datum/unit_test/ownership_identity

/datum/unit_test/ownership_identity/Run()
	// Parking and unparking a handle slot (latent collapse / re-materialize).
	var/datum/own_test_holder/H = new
	var/datum/own_test_child/A = new
	rel_set(H, nameof(H.view), A)
	var/h = om_handle(A)
	var/id = om_handle_park(A)
	qdel(A)
	TEST_ASSERT(isnull(H.view), "the view clears when the collapsed thing goes")
	TEST_ASSERT(isnull(om_resolve(h)), "a parked handle resolves to nothing")
	var/datum/own_test_child/B = new
	om_handle_unpark(B, id)
	TEST_ASSERT_EQUAL(om_resolve(h), B, "the re-materialized thing takes over the old handle")
	TEST_ASSERT_EQUAL(H.view, B, "and the dormant view re-links to it")
	// replace_with forwarding.
	var/datum/own_test_child/C = new
	om_handle_forward(B, C)
	TEST_ASSERT_EQUAL(H.view, C, "om_handle_forward re-points views to the successor")
	TEST_ASSERT_EQUAL(om_resolve(h), C, "and hands it the handle slot")
	// A successor of another family (an airlock torn down into an assembly) is a new thing:
	// the views and handle stay with the original and end with it.
	var/datum/own_test_holder/other = new
	om_handle_forward(C, other)
	TEST_ASSERT_EQUAL(H.view, C, "om_handle_forward leaves views on the original for a successor of another family")
	TEST_ASSERT_EQUAL(om_resolve(h), C, "and keeps the handle slot")
	qdel(other)
	qdel(B)
	qdel(C)
	TEST_ASSERT(isnull(H.view), "the view ends with the original")
	qdel(H)

/datum/unit_test/ownership_rec_audit

/datum/unit_test/ownership_rec_audit/Run()
	own_rec_audit_make_dropped()
	var/list/lines = own_audit(quiet = TRUE)
	var/found = FALSE
	for(var/line in lines)
		if(findtext(line, "dropped with a rec") && findtext(line, "/datum/own_test_child"))
			found = TRUE
	TEST_ASSERT(found, "an entity held only by its own OM record (a live timer) is found and torn down: [json_encode(lines)]")

/// Makes an entity nothing owns or references except its own record (a pending timer).
/proc/own_rec_audit_make_dropped()
	var/datum/own_test_child/A = new
	after(A, 10 MINUTES, TYPE_PROC_REF(/datum/own_test_child, test_label))

/datum/own_test_field_holder
OM_FIELD_VIEW(/datum/own_test_field_holder, tmp/datum/own_test_child, watched, CHANGE_MACHINE_SETTINGS)

/datum/unit_test/ownership_framework_writes_raise_fields

/datum/unit_test/ownership_framework_writes_raise_fields/Run()
	var/datum/own_test_field_holder/H = new
	var/datum/own_test_child/T = new
	var/datum/om/scheduler/sched = om_scheduler()
	om_rec_of(H)
	H.om_listen |= CHANGE_MACHINE_SETTINGS
	sched.test_raises = list()
	rel_set(H, nameof(H.watched), T)
	TEST_ASSERT(own_test_raised(sched, H), "a relation write to a declared field raises its channel")
	sched.test_raises = list()
	qdel(T)
	TEST_ASSERT(isnull(H.watched), "the view cleared when its target died")
	TEST_ASSERT(own_test_raised(sched, H), "the automatic clear of a declared field raises its channel, as the setter would")
	sched.test_raises = null
	qdel(H)

/proc/own_test_raised(datum/om/scheduler/sched, datum/E)
	for(var/list/raise as anything in sched.test_raises)
		if(raise[1] == E && (raise[2] & CHANGE_MACHINE_SETTINGS))
			return TRUE
	return FALSE

// ---- ownership() / relations() entries: policies, rel_link pairs, hooks, watch ----

/datum/own_test_policy_holder
	var/obj/spilled
	var/obj/conditional
	var/datum/own_test_child/by_proc
	var/datum/own_test_child/plain
	var/keep_it = FALSE

/datum/own_test_policy_holder/ownership()
	. = ..()
	. += owns(nameof(spilled), policy = OWN_SPILL)
	. += owns(nameof(conditional), policy = OWN_SPILL, if_var = nameof(keep_it), else_policy = OWN_DELETE)
	. += owns(nameof(by_proc), policy_proc = TYPE_PROC_REF(/datum/own_test_policy_holder, by_proc_policy))
	. += owns(nameof(plain), policy = OWN_NONE, keep_after_destroy = TRUE)

/datum/own_test_policy_holder/proc/by_proc_policy()
	return keep_it ? OWN_CONTAINED : OWN_DELETE

/datum/unit_test/ownership_declared_policies

/datum/unit_test/ownership_declared_policies/Run()
	var/datum/own_test_policy_holder/H = new
	var/datum/own_table/table = own_table_of(H)
	TEST_ASSERT_EQUAL(own_policy(H, nameof(H.spilled), table.entries[nameof(H.spilled)]), OWN_SPILL, "policy = sets the policy")
	TEST_ASSERT_EQUAL(own_policy(H, nameof(H.conditional), table.entries[nameof(H.conditional)]), OWN_DELETE, "else_policy applies while if_var is false")
	TEST_ASSERT_EQUAL(own_policy(H, nameof(H.by_proc), table.entries[nameof(H.by_proc)]), OWN_DELETE, "policy_proc is asked")
	H.keep_it = TRUE
	TEST_ASSERT_EQUAL(own_policy(H, nameof(H.conditional), table.entries[nameof(H.conditional)]), OWN_SPILL, "policy applies while if_var is true")
	TEST_ASSERT_EQUAL(own_policy(H, nameof(H.by_proc), table.entries[nameof(H.by_proc)]), OWN_CONTAINED, "policy_proc answers from state")
	TEST_ASSERT(isnull(table.entries[nameof(H.plain)]), "an annotation-only owns(policy = OWN_NONE) declares no kind")
	TEST_ASSERT(nameof(H.plain) in table.keep_vars, "keep_after_destroy is recorded")
	qdel(H)

/datum/own_test_watch_target
	var/power_level = 0
	var/label = "x"
TRACKED_BRIDGED(/datum/own_test_watch_target, power_level, CHANGE_EFFECTS)

/datum/own_test_watch_holder
	var/datum/own_test_watch_target/watched
	var/datum/own_test_watch_target/unwatched

/datum/own_test_watch_holder/relations()
	. = ..()
	. += rel_one(nameof(watched), watch = list(nameof(/datum/own_test_watch_target::power_level)))
	. += rel_one(nameof(unwatched))

/datum/unit_test/ownership_watched_relation

/datum/unit_test/ownership_watched_relation/Run()
	var/datum/own_test_watch_holder/H = new
	var/datum/own_test_watch_target/T = new
	var/datum/own_test_watch_target/U = new
	rel_link(H, nameof(H.watched), T)
	rel_link(H, nameof(H.unwatched), U)
	refresh_flush()
	TEST_ASSERT(!H.refresh_queued, "nothing queued after the flush")
	U.set_power_level(3)
	TEST_ASSERT(!H.refresh_queued, "a change on an unwatched relation does not mark the holder")
	refresh_flush()
	T.set_power_level(5)
	TEST_ASSERT(H.refresh_queued, "a setter on the watched target marks the holder changed")
	refresh_flush()
	rel_unlink(H, nameof(H.watched), T)
	T.set_power_level(7)
	TEST_ASSERT(!H.refresh_queued, "an unlinked target no longer marks the holder")
	refresh_flush()
	qdel(T)
	qdel(U)
	qdel(H)

/datum/unit_test/ownership_rel_link_pairs

/datum/unit_test/ownership_rel_link_pairs/Run()
	var/datum/own_test_holder/H = new
	var/datum/own_test_partner/P = new
	var/datum/own_test_member/M = new
	var/datum/own_test_holder/H2 = new
	// back = on a rel_one(): one call writes both sides.
	TEST_ASSERT_EQUAL(rel_link(H, nameof(H.partner), P), P, "rel_link returns the target")
	TEST_ASSERT_EQUAL(P.holder, H, "rel_link on a rel_one(back =) sets the other side")
	// back = on a rel_many(): the many side is a list, the one side single.
	rel_link(M, nameof(M.group), H)
	TEST_ASSERT(M in H.members, "linking the one side adds us to the other's rel_many()")
	TEST_ASSERT(rel_unlink(H, nameof(H.members), M), "rel_unlink reports the unlink")
	TEST_ASSERT(isnull(M.group) && !(M in H.members), "rel_unlink clears both sides")
	// rel_many(back = this var): symmetric membership.
	rel_link(H, nameof(H.peers), H2)
	TEST_ASSERT((H2 in H.peers) && (H in H2.peers), "a symmetric rel_many() lists each in the other")
	rel_unlink(H2, nameof(H2.peers))
	TEST_ASSERT(!(H2 in H.peers) && !length(H2.peers), "rel_unlink with no target empties both sides")
	TEST_ASSERT(!rel_unlink(H, nameof(H.partner), M), "unlinking something not linked is refused")
	qdel(P)
	TEST_ASSERT(isnull(H.partner), "the partner's death clears the view")
	qdel(M)
	qdel(H2)
	qdel(H)

/datum/own_test_hook_holder
	var/datum/own_test_child/subject
	var/datum/own_test_child/tracked
	var/list/unlinked

/datum/own_test_hook_holder/relations()
	. = ..()
	. += rel_one(nameof(subject), other_deleted = DELETE_ME)
	. += rel_one(nameof(tracked), on_unlink = PROC_REF(tracked_gone))

/datum/own_test_hook_holder/proc/tracked_gone(datum/other)
	LAZYADD(unlinked, other)

/datum/unit_test/ownership_rel_hooks

/datum/unit_test/ownership_rel_hooks/Run()
	var/datum/own_test_hook_holder/H = new
	var/datum/own_test_child/T1 = new
	var/datum/own_test_child/T2 = new
	rel_link(H, nameof(H.tracked), T1)
	rel_link(H, nameof(H.tracked), T2)
	TEST_ASSERT(length(H.unlinked) == 1 && H.unlinked[1] == T1, "replacing a link runs on_unlink with the old target")
	qdel(T2)
	TEST_ASSERT(isnull(H.tracked), "the target's death clears the view")
	TEST_ASSERT(length(H.unlinked) == 2 && H.unlinked[2] == T2, "the target's death runs on_unlink with the dying target")
	rel_link(H, nameof(H.tracked), T1)
	rel_unlink(H, nameof(H.tracked), T1)
	TEST_ASSERT(length(H.unlinked) == 3 && H.unlinked[3] == T1, "rel_unlink runs on_unlink")
	H.unlinked = null
	var/datum/own_test_child/S = new
	rel_link(H, nameof(H.subject), S)
	qdel(S)
	TEST_ASSERT(QDELETED(H), "other_deleted = DELETE_ME deletes the holder with the other end")
	qdel(T1)

/datum/own_test_keep_holder
	var/datum/own_test_child/kept

/datum/own_test_keep_holder/ownership()
	. = ..()
	. += owns(nameof(kept), policy = OWN_KEEP)

/datum/unit_test/ownership_keep_policy

/datum/unit_test/ownership_keep_policy/Run()
	var/datum/own_test_keep_holder/H = new
	var/datum/own_test_child/C = new
	rel_set(H, nameof(H.kept), C)
	TEST_ASSERT_EQUAL(owner_of(C), H, "an OWN_KEEP value is owned while its holder lives")
	qdel(H)
	TEST_ASSERT(!QDELETED(C), "OWN_KEEP: the value outlives its holder")
	TEST_ASSERT(isnull(owner_of(C)), "OWN_KEEP: the value is released at teardown")
	qdel(C)

/// A slot capability owns its var: the type declares nothing in ownership().
/obj/cap_fixture/own_slot_holder
	var/obj/item/cell/cell

/obj/cap_fixture/own_slot_holder/capabilities()
	. = ..()
	. += cap_slot(nameof(cell), /obj/item/cell)

/datum/unit_test/ownership_capability_owned

/datum/unit_test/ownership_capability_owned/Run()
	var/obj/cap_fixture/own_slot_holder/H = allocate(/obj/cap_fixture/own_slot_holder)
	var/list/entry = own_table_of(H).entries[nameof(H.cell)]
	TEST_ASSERT_NOTNULL(entry, "the slot capability's owned() declares its var in the holder's table")
	TEST_ASSERT_EQUAL(entry[OWNE_KIND], OWNK_OWN, "the slot var is owned")
	TEST_ASSERT_EQUAL(entry[OWNE_ARG], OWN_CONTAINED, "the slot var is owned CONTAINED")
