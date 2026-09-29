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

REL_PAIR(/datum/own_test_holder, partner, holder)
REL_PAIR(/datum/own_test_partner, holder, partner)
REL_PAIR_LIST(/datum/own_test_holder, members, group)
REL_PAIR(/datum/own_test_member, group, members)
REL_SET(/datum/own_test_holder, peers)
PROTO(/datum/own_test_holder, species)

/datum/own_test_holder/on_owned_release(var_name, datum/child)
	. = ..()
	released++

/datum/own_test_child
	var/label = "child"
	var/datum/own_test_child/grandchild

/datum/own_test_partner
	var/datum/own_test_holder/holder

/datum/own_test_member
	var/datum/own_test_holder/group

/obj/own_test_keyed_source
	var/key = "k1"
	var/obj/own_test_keyed_target/target

REL_KEYED(/obj/own_test_keyed_source, target, key, /obj/own_test_keyed_target)

/obj/own_test_keyed_target
	var/id = "k1"

KEYED_TARGET(/obj/own_test_keyed_target, id)

/datum/unit_test/ownership_own_accessors

/datum/unit_test/ownership_own_accessors/Run()
	var/list/capture = list()
	GLOB.dq_lifecycle_report_capture = capture
	var/datum/own_test_holder/H = new
	var/datum/own_test_child/A = new
	own_set(H, "child", A)
	TEST_ASSERT_EQUAL(H.child, A, "own_set writes the var")
	TEST_ASSERT_EQUAL(owner_of(A), H, "the owner is stamped on the child")
	TEST_ASSERT_EQUAL(owner_slot_of(A), "child", "the owner's var is stamped on the child")
	var/datum/own_test_child/B = new
	own_set(H, "child", B)
	TEST_ASSERT(QDELETED(A), "own_set destroys the value it replaces (DELETE policy)")
	TEST_ASSERT(H.released >= 1, "the owned-child release hook ran")
	var/datum/own_test_child/taken = own_take(H, "child")
	TEST_ASSERT_EQUAL(taken, B, "own_take returns the value")
	TEST_ASSERT(isnull(H.child) && isnull(owner_of(B)), "own_take detaches and unstamps")
	own_add(H, "children", B)
	own_put(H, "values", "a", new /datum/own_test_child)
	TEST_ASSERT(B in H.children, "own_add adds to the owned list")
	var/datum/own_test_holder/H2 = new
	own_transfer(H, "children", H2, "child", B)
	TEST_ASSERT_EQUAL(H2.child, B, "own_transfer moves a list member into another owner's var")
	TEST_ASSERT_EQUAL(owner_of(B), H2, "the move restamps the owner")
	TEST_ASSERT(!length(H.children), "the source list no longer holds it")
	TEST_ASSERT(!length(capture), "no reports for legal moves: [json_encode(capture)]")
	// Double ownership is refused.
	own_set(H, "child", B)
	TEST_ASSERT(length(capture) == 1 && findtext(capture[1], "already owned"), "adopting a value another holder owns is reported: [json_encode(capture)]")
	TEST_ASSERT_EQUAL(owner_of(B), H2, "the refused adoption leaves the owner alone")
	capture.Cut()
	// own_move finds the current owner itself.
	own_move(B, H, "child")
	TEST_ASSERT(H.child == B && isnull(H2.child), "own_move transfers from whatever owns it")
	var/datum/own_test_child/V = H.values["a"]
	qdel(H)
	TEST_ASSERT(QDELETED(B) && QDELETED(V), "destroying the owner deletes its owned values")
	qdel(H2)
	GLOB.dq_lifecycle_report_capture = null
	TEST_ASSERT(!length(capture), "no reports: [json_encode(capture)]")

/datum/unit_test/ownership_phase8_reset

/datum/unit_test/ownership_phase8_reset/Run()
	var/list/capture = list()
	GLOB.dq_lifecycle_report_capture = capture
	var/datum/own_test_holder/H = new
	own_set(H, "child", new /datum/own_test_child)
	dq_lifecycle_clear_links(H) // phase 4
	var/datum/own_test_child/late = new
	H.child = late // ALLOW(ownership): the test re-sets an owned var after phase 4
	own_scrub(H) // phase 8
	GLOB.dq_lifecycle_report_capture = null
	TEST_ASSERT(QDELETED(late), "phase 8 deletes a value re-set during teardown")
	TEST_ASSERT(length(capture) && findtext(capture[1], "re-set during teardown"), "and reports it: [json_encode(capture)]")
	qdel(H)

/datum/unit_test/ownership_orphan_audit

/datum/unit_test/ownership_orphan_audit/Run()
	var/datum/own_test_holder/H = new
	var/datum/own_test_child/A = new
	own_set(H, "child", A)
	H.child = null // ALLOW(ownership): the test drops an owned value without the accessors
	var/list/lines = own_audit(quiet = TRUE)
	var/found = FALSE
	for(var/line in lines)
		if(findtext(line, "orphan") && findtext(line, "/datum/own_test_child"))
			found = TRUE
	TEST_ASSERT(found, "the audit finds a value dropped without own_take/own_set: [json_encode(lines)]")
	qdel(A)
	qdel(H)

/datum/unit_test/ownership_relation_views

/datum/unit_test/ownership_relation_views/Run()
	var/list/capture = list()
	GLOB.dq_lifecycle_report_capture = capture
	var/datum/own_test_holder/H = new
	var/datum/own_test_child/T = new
	rel_set(H, "view", T)
	TEST_ASSERT_EQUAL(H.view, T, "rel_set writes the view")
	qdel(T)
	TEST_ASSERT(isnull(H.view), "the target's death clears the view")
	// Pairs set both sides; exclusivity unlinks the old partner.
	var/datum/own_test_partner/P1 = new
	var/datum/own_test_partner/P2 = new
	rel_set(H, "partner", P1)
	TEST_ASSERT_EQUAL(P1.holder, H, "a pair sets the partner's side")
	rel_set(P2, "holder", H)
	TEST_ASSERT(H.partner == P2 && isnull(P1.holder), "linking a new partner unlinks the old one on both sides")
	// 1:N pairs.
	var/datum/own_test_member/M1 = new
	var/datum/own_test_member/M2 = new
	rel_set(M1, "group", H)
	rel_add(H, "members", M2)
	TEST_ASSERT((M1 in H.members) && M2.group == H, "either side of a 1:N pair links both")
	qdel(M1)
	TEST_ASSERT(!(M1 in H.members), "a member's death leaves the list")
	// Symmetric membership.
	var/datum/own_test_holder/Q = new
	rel_add(H, "peers", Q)
	TEST_ASSERT((Q in H.peers) && (H in Q.peers), "REL_SET links both ends")
	// The source's death clears its partners' sides.
	qdel(H)
	TEST_ASSERT(isnull(P2.holder) && isnull(M2.group) && !(H in Q.peers), "the source's death clears every partner side")
	TEST_ASSERT(!length(P2.om_refs_in) && !length(Q.om_refs_in), "and every reverse index entry")
	// Linking to a dying entity is refused.
	var/datum/own_test_holder/H3 = new
	var/datum/own_test_child/dying = new
	dying.gc_destroyed = GC_CURRENTLY_BEING_QDELETED
	rel_set(H3, "view", dying)
	dying.gc_destroyed = null
	TEST_ASSERT(isnull(H3.view), "a link to an entity being destroyed is refused")
	GLOB.dq_lifecycle_report_capture = null
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
	rel_set(H, "view", T)
	TEST_ASSERT_EQUAL(H.view, T, "a turf can be a relation target")
	var/list/by_turf = GLOB.rel_turf_index["[T.z]"]
	TEST_ASSERT(by_turf && by_turf[own_key(T)], "a view naming a turf is indexed under its z-level")
	rel_clear(H, "view")
	var/list/index = by_turf ? by_turf[own_key(T)] : null
	TEST_ASSERT(!index || !index[own_key(H)], "clearing the view leaves the turf index")
	// Releasing a z-level clears every view naming its turfs. The test map's own z-level holds the
	// harness's views too, so the release is exercised on a private key with this turf's entry.
	rel_set(H, "view", T)
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
	proto_set(H, "species", proto)
	TEST_ASSERT(!proto_is_private(H, "species"), "a registered prototype is shared")
	var/datum/species/mine = proto_private(H, "species")
	TEST_ASSERT(mine != proto && proto_is_private(H, "species"), "proto_private makes an owned private copy")
	TEST_ASSERT(proto_private(H, "species") == mine, "and returns the same copy afterwards")
	proto_set(H, "species", proto)
	TEST_ASSERT(QDELETED(mine), "proto_set deletes the private copy it replaces")
	var/datum/species/second = proto_private(H, "species")
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
	GLOB.dq_lifecycle_report_capture = capture
	var/datum/own_test_holder/H = new
	shared_set(H, "view", copy)
	GLOB.dq_lifecycle_report_capture = null
	TEST_ASSERT(length(capture) && findtext(capture[1], "not a registered instance"), "shared_set refuses an unregistered value: [json_encode(capture)]")
	H.view = null // ALLOW(ownership): test cleanup of a deliberately wrong write
	qdel(copy)
	qdel(H)

/datum/unit_test/ownership_entity_clone

/datum/unit_test/ownership_entity_clone/Run()
	var/datum/own_test_holder/H = new
	var/datum/own_test_child/A = new
	A.label = "original"
	own_set(A, "grandchild", new /datum/own_test_child)
	own_set(H, "child", A)
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
	var/list/capture = om_capture_args(list(list("nested" = list(A)), 3))
	TEST_ASSERT(capture, "a nested datum is captured")
	var/list/captured = capture[1]
	TEST_ASSERT(!findtext(json_encode(captured), "\[0x"), "no reference survives in the capture")
	var/list/copy = captured.Copy()
	TEST_ASSERT(om_resolve_captured(copy, capture[2]), "it resolves while the datum lives")
	var/list/outer = copy[1]
	var/list/inner = outer["nested"]
	TEST_ASSERT_EQUAL(inner[1], A, "back to the datum")
	qdel(A)
	copy = captured.Copy()
	TEST_ASSERT(!om_resolve_captured(copy, capture[2]), "and refuses once it is gone")
	var/list/reports = list()
	GLOB.dq_lifecycle_report_capture = reports
	var/datum/own_test_child/K = new
	var/list/keyed = list()
	keyed[K] = 1
	TEST_ASSERT(isnull(om_capture_args(list(keyed))), "a datum used as an assoc key is refused")
	GLOB.dq_lifecycle_report_capture = null
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
	rel_set(H, "view", A)
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
	om_after(A, 10 MINUTES, TYPE_PROC_REF(/datum/own_test_child, test_label))

/datum/own_test_field_holder
OM_FIELD_TYPED(/datum/own_test_field_holder, tmp/datum/own_test_child, watched, null, CHANGE_MACHINE_SETTINGS)

/datum/unit_test/ownership_framework_writes_raise_fields

/datum/unit_test/ownership_framework_writes_raise_fields/Run()
	var/datum/own_test_field_holder/H = new
	var/datum/own_test_child/T = new
	var/datum/om/scheduler/sched = om_scheduler()
	om_rec_of(H)
	H.om_listen |= CHANGE_MACHINE_SETTINGS
	sched.test_raises = list()
	rel_set(H, "watched", T)
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
