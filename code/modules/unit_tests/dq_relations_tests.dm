// Relations wave 0 (doc/rewrite/proposals/relations.md D1, D3, D14, D17): an undeclared write is reported, vars_write goes through the
// relation verbs, a link end cannot also be another declaration, and a thing that survives its container is spilled, not deleted.

/// A holder with a var no declaration names (the write below is by a dynamic name, so the rel_write_undeclared lint does not see it).
/datum/relations_stray_holder
	var/datum/stray
	var/datum/declared

CAPABILITIES(/datum/relations_stray_holder)
	ref_one(nameof(declared))

/datum/unit_test/relations_undeclared_write_reported

/datum/unit_test/relations_undeclared_write_reported/Run()
	var/list/capture = list()
	set_global("dq_lifecycle_report_capture", capture)
	var/datum/relations_stray_holder/H = new
	var/datum/relations_stray_holder/other = new
	rel_set(H, "declared", other)
	TEST_ASSERT_EQUAL(H.declared, other, "a declared var is written")
	TEST_ASSERT(!length(capture), "a declared write reports nothing: [json_encode(capture)]")
	rel_set(H, "stray", other)
	set_global("dq_lifecycle_report_capture", null)
	TEST_ASSERT(length(capture) == 1 && findtext(capture[1], "not declared"), "an undeclared write is reported, not learned: [json_encode(capture)]")
	var/datum/own_table/T = own_table_of(H)
	TEST_ASSERT(isnull(T.entries["stray"]), "the table learned nothing from the write")
	qdel(H)
	qdel(other)

/datum/unit_test/relations_vars_write_routes_relation

/datum/unit_test/relations_vars_write_routes_relation/Run()
	var/list/reports = list()
	set_global("declare_report_capture", reports)
	var/datum/own_test_holder/H = new
	var/datum/own_test_child/target = new
	TEST_ASSERT(vars_write(H, "view", target), "vars_write writes a declared relation var")
	TEST_ASSERT_EQUAL(H.view, target, "the value is held")
	qdel(target)
	TEST_ASSERT(isnull(H.view), "the write went through the relation: the target's death cleared the view")
	TEST_ASSERT(!vars_write(H, "view", 5), "a number is not an entity")
	TEST_ASSERT(!vars_write(H, "children", 5), "a many takes a list of entities, not a number")
	set_global("declare_report_capture", null)
	TEST_ASSERT_EQUAL(length(reports), 2, "both refusals are reported: [json_encode(reports)]")
	var/datum/own_test_child/first = new
	var/datum/own_test_child/second = new
	TEST_ASSERT(vars_write(H, "children", list(first, second)), "a many is refilled from a list")
	TEST_ASSERT(length(H.children) == 2 && (first in H.children) && (second in H.children), "both members are held")
	TEST_ASSERT_EQUAL(owner_of(first), H, "the owner stamp was written: the write used the verbs")
	TEST_ASSERT(vars_write(H, "children", null), "null empties a many")
	TEST_ASSERT(!length(H.children), "the list is empty")
	qdel(H)

/obj/item/dq_relations_survivor
	name = "survivor"
	w_class = ITEMSIZE_SMALL

/obj/item/dq_relations_survivor/survives_container()
	return TRUE

/datum/unit_test/relations_survives_container_spills

/datum/unit_test/relations_survives_container_spills/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_destroy_transaction_nest_outer/outer = allocate(/obj/item/dq_destroy_transaction_nest_outer, T)
	var/obj/item/dq_relations_survivor/survivor = allocate(/obj/item/dq_relations_survivor, T)
	var/obj/item/dq_containment_test/plain = allocate(/obj/item/dq_containment_test, T)
	TEST_ASSERT(move_into(outer, null, survivor), "the survivor into the deleting slot")
	TEST_ASSERT(move_into(outer, null, plain), "an ordinary item into the same slot")
	qdel(outer)
	TEST_ASSERT(QDELETED(plain), "the DELETE slot deleted the ordinary item")
	TEST_ASSERT(!QDELETED(survivor), "the thing that survives its container was not deleted")
	TEST_ASSERT_EQUAL(survivor.loc, T, "it spilled to where the holder was")

/datum/unit_test/relations_survives_container_defaults

/datum/unit_test/relations_survives_container_defaults/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_containment_test/plain = allocate(/obj/item/dq_containment_test, T)
	TEST_ASSERT(!plain.survives_container(), "an ordinary item does not survive its container")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human/dummy, T)
	TEST_ASSERT(!H.survives_container(), "a mob with no mind and no client does not")
	var/obj/item/disk/nuclear/disk = allocate(/obj/item/disk/nuclear, T)
	TEST_ASSERT(disk.survives_container(), "the nuclear disk does")

/// Two ends of a refusing var pair (D3): a dock takes one ship and a ship one dock; a second link on either side is refused.
/datum/relations_refuse_dock
	var/datum/relations_refuse_ship/ship

/datum/relations_refuse_ship
	var/datum/relations_refuse_dock/dock

CAPABILITIES(/datum/relations_refuse_dock)
	links(/datum/relations_refuse_dock::ship, /datum/relations_refuse_ship::dock, conflict = REFUSE)

/datum/unit_test/relations_var_pair_refuses

/datum/unit_test/relations_var_pair_refuses/Run()
	var/list/capture = list()
	set_global("dq_lifecycle_report_capture", capture)
	var/datum/relations_refuse_dock/dock = new
	var/datum/relations_refuse_dock/other_dock = new
	var/datum/relations_refuse_ship/ship = new
	var/datum/relations_refuse_ship/other_ship = new
	TEST_ASSERT_EQUAL(rel_set(dock, nameof(dock.ship), ship), ship, "a free pair links")
	TEST_ASSERT_EQUAL(ship.dock, dock, "and both ends name each other")
	TEST_ASSERT_NULL(rel_try_set(dock, nameof(dock.ship), other_ship), "a dock that holds a ship refuses another")
	TEST_ASSERT_EQUAL(dock.ship, ship, "the old link stays")
	TEST_ASSERT_NULL(other_ship.dock, "the refused ship names nothing")
	TEST_ASSERT_NULL(rel_try_set(other_dock, nameof(other_dock.ship), ship), "a ship already docked refuses another dock")
	TEST_ASSERT_EQUAL(ship.dock, dock, "the ship keeps its dock")
	TEST_ASSERT_NULL(other_dock.ship, "the refused dock names nothing")
	rel_set(dock, nameof(dock.ship), null)
	TEST_ASSERT_NULL(ship.dock, "unlinking clears both ends")
	TEST_ASSERT_EQUAL(rel_set(other_dock, nameof(other_dock.ship), ship), ship, "a freed ship links to another dock")
	TEST_ASSERT(!length(capture), "an expected refusal (rel_try_set) reports nothing: [json_encode(capture)]")
	rel_set(dock, nameof(dock.ship), ship)
	set_global("dq_lifecycle_report_capture", null)
	TEST_ASSERT(length(capture) == 1 && findtext(capture[1], "refused by links"), "a plain rel_set that is refused reports: [json_encode(capture)]")
	TEST_ASSERT_EQUAL(ship.dock, other_dock, "and changes nothing")
	qdel(dock)
	qdel(other_dock)
	qdel(ship)
	qdel(other_ship)

/// D7 structural reset check: every pooled type returns every field to its fresh value on release, so a field added later cannot keep a
/// reference into the next taker's use. This is why the stored_refs lint treats a pooled holder's fields as transient.
/datum/unit_test/relations_pooled_release_resets_every_field

/datum/unit_test/relations_pooled_release_resets_every_field/Run()
	set_global("pool_poison", FALSE)
	var/datum/probe = new
	var/checked = 0
	for(var/T in subtypesof(/datum/pooled))
		var/datum/pooled/proto = T
		if(initial(proto.abstract_type) == T || T == /datum/pool_probe) // the probe counts its own resets on purpose (dq_foundation_look_tests.dm)
			continue
		var/datum/pooled/P = take(T)
		var/list/fresh = P.snapshot()
		var/list/plan = pool_reset_plan(P)
		for(var/name in plan)
			if(plan[name] == POOL_RESET_LIST)
				var/list/L = P.vars[name]
				L += probe
			else
				P.vars[name] = probe
		P.release()
		var/datum/pooled/again = take(T)
		var/list/after = again.snapshot()
		for(var/name in fresh)
			TEST_ASSERT_EQUAL(after[name], fresh[name], "[T].[name] is back to its fresh value after release")
		again.release()
		checked++
	TEST_ASSERT(checked > 0, "some pooled type was checked")
	qdel(probe)

/// A weak reference (D5): the var holds a handle, the generated accessor reads the target or null, and nothing pins or indexes it.
/datum/relations_weak_holder
	var/tmp/watched
	var/tmp/list/seen

/datum/relations_weak_target

CAPABILITIES(/datum/relations_weak_holder)
	ref_one(nameof(watched), /datum/relations_weak_target, weak = TRUE)
	ref_many(nameof(seen), /datum/relations_weak_target, weak = TRUE)

/datum/unit_test/relations_weak_reference

/datum/unit_test/relations_weak_reference/Run()
	var/list/capture = list()
	set_global("dq_lifecycle_report_capture", capture)
	var/datum/relations_weak_holder/H = new
	var/datum/relations_weak_target/T = new
	var/datum/relations_weak_target/U = new
	TEST_ASSERT_EQUAL(rel_set(H, nameof(H.watched), T), T, "a weak one is written")
	TEST_ASSERT(istext(H.watched), "the var holds a handle, not the datum")
	TEST_ASSERT_EQUAL(H.watched(), T, "the accessor reads the target")
	TEST_ASSERT_EQUAL(rel_kind(H, nameof(H.watched)), OWNK_WEAK, "declared weak")
	rel_add(H, nameof(H.seen), T)
	rel_add(H, nameof(H.seen), U)
	rel_add(H, nameof(H.seen), U)
	TEST_ASSERT_EQUAL(length(H.seen()), 2, "a weak many holds each member once")
	TEST_ASSERT(!length(rel_sources(T)), "nothing is indexed on the target")
	qdel(T)
	TEST_ASSERT_NULL(H.watched(), "the accessor reads null once the target is gone")
	var/list/live = H.seen()
	TEST_ASSERT(length(live) == 1 && live[1] == U, "a weak many reads only live members")
	rel_remove(H, nameof(H.seen), U)
	TEST_ASSERT_EQUAL(length(H.seen()), 0, "a member is removed")
	rel_clear(H, nameof(H.watched))
	TEST_ASSERT_NULL(H.watched, "cleared")
	set_global("dq_lifecycle_report_capture", null)
	TEST_ASSERT(!length(capture), "weak writes report nothing: [json_encode(capture)]")
	qdel(H)
	qdel(U)

/// D10: a client handle names one connection ("@ckey#n"). The old bare "@ckey" form names nothing, and a connection number that is not the live
/// client's resolves null (a reconnect is a new /client with a new number). A test world has no client, so this pins the resolver's forms.
/datum/unit_test/relations_client_handle_forms

/datum/unit_test/relations_client_handle_forms/Run()
	TEST_ASSERT_NULL(resolve_token("@nobody"), "a bare ckey handle names nothing")
	TEST_ASSERT_NULL(resolve_token("@nobody#1"), "a handle of a ckey that is not connected names nothing")

/// A subtype's links() end over a var an ancestor declares as a plain ref_one refines it into a pair: no declaration report, and both ends are
/// maintained (the blob resource's overmind, an ancestor ref_one, is one end of links(... /mob/observer/blob::resource_blobs)).
/datum/relations_refine_base
	var/datum/relations_refine_hub/hub

CAPABILITIES(/datum/relations_refine_base)
	ref_one(nameof(hub))

/datum/relations_refine_base/linked

/datum/relations_refine_hub
	var/list/members

CAPABILITIES(/datum/relations_refine_base/linked)
	links(/datum/relations_refine_base/linked::hub, /datum/relations_refine_hub::members, b_many = TRUE)

/datum/unit_test/relations_link_refines_ancestor_ref

/datum/unit_test/relations_link_refines_ancestor_ref/Run()
	var/list/capture = list()
	set_global("dq_lifecycle_report_capture", capture)
	var/datum/relations_refine_base/linked/L = new
	var/datum/relations_refine_hub/H = new
	rel_set(L, nameof(L.hub), H)
	TEST_ASSERT(L in H.members, "the subtype's end is a pair: the hub lists it")
	var/obj/structure/blob/resource/R = allocate(/obj/structure/blob/resource, test_floor())
	TEST_ASSERT_EQUAL(own_table_of(R).entries[nameof(R.overmind)][OWNE_ARG], RELS_PAIR, "the blob resource's overmind is the pair's end")
	set_global("dq_lifecycle_report_capture", null)
	TEST_ASSERT(!length(capture), "an ancestor ref refined by a link reports nothing: [json_encode(capture)]")
	qdel(L)
	TEST_ASSERT(!length(H.members), "the pair clears with its end")
	qdel(H)

/// D11: an image shown through client_images_add() is indexed by the atom it rides on, and that atom's death drops the index (no client in a
/// test world, so this pins the index the teardown walks).
/datum/unit_test/relations_client_images_index

/datum/unit_test/relations_client_images_index/Run()
	var/obj/item/pen/P = allocate(/obj/item/pen, test_floor())
	var/image/I = image('icons/obj/bureaucracy.dmi', P, "pen")
	var/list/riding = list(I)
	GLOB.client_images_by_loc[P] = riding
	TEST_ASSERT(GLOB.client_images_by_loc[P], "the index names the atom the image rides on")
	qdel(P)
	TEST_ASSERT_NULL(GLOB.client_images_by_loc[P], "a dying atom drops its images from the index")

/// D12: a member that joined a registry while globals initialized (the global message listener, made by GLOB) is in the membership store once
/// the store (made on first use, so it exists from global init) recorded the join, so the one leave path finds it.
/datum/unit_test/relations_registry_global_init_members_adopted

/datum/unit_test/relations_registry_global_init_members_adopted/Run()
	var/datum/listener = GLOB.global_message_listener
	TEST_ASSERT(listener in REGISTRY_MEMBERS(REGISTRY_COMM_MESSAGE_LISTENERS), "the global listener joined at global init")
	TEST_ASSERT(member_is("registry:[REGISTRY_COMM_MESSAGE_LISTENERS]", listener), "and the store knows it")

/// The work_queues exemption (lint_scopes.toml) holds only while a deleted member never outlives the next drain. Lighting: a source queued
/// for an update leaves the queue when it is deleted, and the drain runs clean.
/datum/unit_test/relations_work_queue_lighting_sources

/datum/unit_test/relations_work_queue_lighting_sources/Run()
	var/obj/F = allocate(/obj, test_floor()) // a static light source (a flashlight uses overlay lighting, no source)
	F.set_light_range(4)
	F.set_light_power(1)
	F.set_light_on(TRUE)
	F.update_light()
	var/datum/light_source/L = F.light
	TEST_ASSERT(L, "a lit object has a light source")
	if(!(L in SSlighting.sources_queue))
		SSlighting.sources_queue += L // queued for an update, as any change does
	qdel(F)
	TEST_ASSERT(!(L in SSlighting.sources_queue), "a deleted source left the work queue")
	SSlighting.light_step(0, TRUE) // drains with no runtime (a runtime fails the test)

/// Radiation: the dirty-turf queue holds turfs (never deleted) and empties on a flush.
/datum/unit_test/relations_work_queue_radiation_turfs

/datum/unit_test/relations_work_queue_radiation_turfs/Run()
	var/turf/T = test_floor()
	SSradiation.dirty_turfs[T] = TRUE
	SSradiation.flush_shielding()
	TEST_ASSERT(!length(SSradiation.dirty_turfs), "a flush drains the dirty-turf queue")
	for(var/thing in SSradiation.dirty_turfs)
		TEST_ASSERT(isturf(thing), "the queue holds only turfs")

/// D12: the awake sunlight handlers are a membership-store set, so a deleted handler leaves it by itself (it used to stay in a static list).
/datum/unit_test/relations_sunlight_handlers_leave_on_delete

/datum/unit_test/relations_sunlight_handlers_leave_on_delete/Run()
	var/datum/probe = new
	member_join(SUNLIGHT_AWAKE_KEY, probe)
	TEST_ASSERT(probe in members_of(SUNLIGHT_AWAKE_KEY), "a handler joins the awake set")
	qdel(probe)
	TEST_ASSERT(!(probe in members_of(SUNLIGHT_AWAKE_KEY)), "a deleted member leaves the awake set")
