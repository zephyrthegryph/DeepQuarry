/datum/object_model/test_lifetime_entity
	var/unlinks = 0
	var/last_reason
	var/delete_on_replacement_link = FALSE

/datum/object_model/test_relation
	parent_type = /datum/object_model/relation
	from_type = /datum/object_model/test_lifetime_entity
	to_type = /datum/object_model/test_lifetime_entity
	shape = OM_REL_ONE_TO_ONE

/datum/object_model/test_relation/on_unlink(datum/source, datum/target, reason)
	var/datum/object_model/test_lifetime_entity/S = source
	S.unlinks++
	S.last_reason = reason

/datum/object_model/test_source_single_relation
	parent_type = /datum/object_model/relation
	from_type = /datum/object_model/test_lifetime_entity
	to_type = /datum/object_model/test_lifetime_entity
	source_single = TRUE

/datum/object_model/test_source_single_relation/on_link(datum/source, datum/target)
	var/datum/object_model/test_lifetime_entity/T = target
	if(T.delete_on_replacement_link)
		qdel(T)

/datum/object_model/test_rich_relation
	parent_type = /datum/object_model/relation
	from_type = /datum/object_model/test_lifetime_entity
	to_type = /datum/object_model/test_lifetime_entity
	rich = TRUE

/datum/object_model/test_declared_owner
	parent_type = /datum/object_model/test_lifetime_entity

/datum/object_model/declaration/test_declared_owner
	target_type = /datum/object_model/test_declared_owner

/datum/object_model/declaration/test_declared_owner/build(datum/object_model/archetype/A)
	A.slot("children", /datum/object_model/test_lifetime_entity, 1, OM_SLOT_TRANSFER)

/datum/object_model/test_owned_field_holder
	parent_type = /datum/object_model/test_declared_owner
	var/datum/object_model/test_lifetime_entity/direct_child

/datum/unit_test/om_owned_field_atomicity

/datum/unit_test/om_owned_field_atomicity/Run()
	var/datum/object_model/test_owned_field_holder/holder = new
	var/datum/object_model/test_lifetime_entity/child = new
	TEST_ASSERT(!OM_CLAIM_FIELD(holder, direct_child, "missing", child), "Invalid slot must reject the child")
	TEST_ASSERT_NULL(holder.direct_child, "Failed claim must roll back the direct field")
	TEST_ASSERT_NULL(om_owner(child), "Failed claim must leave the child unowned")
	TEST_ASSERT(OM_CLAIM_FIELD(holder, direct_child, "children", child), "Declared slot accepts the child")
	TEST_ASSERT_EQUAL(holder.direct_child, child, "The direct field mirrors ownership")
	TEST_ASSERT(om_release(child), "The child can be released")
	TEST_ASSERT_NULL(holder.direct_child, "Release clears the direct field")
	qdel(child)
	qdel(holder)

/datum/object_model/test_order_entity
	var/list/events
	var/id
	var/destroy_calls = 0

/datum/object_model/test_order_entity/Destroy()
	destroy_calls++
	events += id
	return ..()

/datum/object_model/test_reentrant_relation
	parent_type = /datum/object_model/relation
	from_type = /datum/object_model/test_order_entity
	to_type = /datum/object_model/test_order_entity

/datum/object_model/test_reentrant_relation/on_unlink(datum/source, datum/target, reason)
	if(reason != OM_REL_DESTROYING)
		return
	om_destroy(target)
	om_destroy(target)

/datum/object_model/test_replacement_relation
	parent_type = /datum/object_model/relation
	from_type = /datum/object_model/test_lifetime_entity
	to_type = /datum/object_model/test_lifetime_entity
	target_single = TRUE
	var/datum/object_model/test_lifetime_entity/rebind_source

/datum/object_model/test_replacement_relation/on_unlink(datum/source, datum/target, reason)
	if(reason != OM_REL_REPLACED || !rebind_source)
		return
	var/datum/object_model/test_lifetime_entity/rebound = rebind_source
	rebind_source = null
	om_link(rebound, type, target)

/datum/object_model/test_link_hook_deletes_target
	parent_type = /datum/object_model/relation
	from_type = /datum/object_model/test_lifetime_entity
	to_type = /datum/object_model/test_lifetime_entity

/datum/object_model/test_link_hook_deletes_target/on_link(datum/source, datum/target)
	qdel(target)

/datum/object_model/test_release_reentry_owner
	var/datum/destination_to_delete
	var/datum/destination_to_claim
	var/datum/child_to_claim

/datum/object_model/test_release_reentry_owner/om_cache_changed(channel)
	. = ..()
	if(channel == "children" && destination_to_delete)
		var/datum/doomed = destination_to_delete
		destination_to_delete = null
		qdel(doomed)
	if(channel == "children" && destination_to_claim)
		var/datum/new_owner = destination_to_claim
		var/datum/new_child = child_to_claim
		destination_to_claim = null
		child_to_claim = null
		om_claim(new_owner, "children", new_child)

/datum/object_model/test_relation_publication_entity
	var/next_relation_action
	var/relation_mirror = FALSE
	var/relation_notifications = 0
	var/link_hook_unlink = FALSE
	var/unlink_hook_relink = FALSE
	var/datum/object_model/test_relation_publication_entity/relation_target
	var/datum/claim_target_to_delete
	var/datum/object_model/test_relation_publication_entity/rich_target_to_unlink
	var/datum/object_model/test_relation_publication_entity/rich_target_to_relink
	var/datum/object_model/test_relation_publication_entity/rich_winner_to_unlink_on_release
	var/unlink_rich_winner_on_provisional_release = FALSE
	var/rich_claim_saw_provisional = FALSE
	var/datum/object_model/test_relation_publication_entity/owned_target_to_relink
	var/datum/object_model/test_relation_publication_entity/claim_competing_target

/datum/object_model/test_relation_publication_entity/om_cache_changed(channel)
	. = ..()
	if(channel == "relations")
		relation_notifications++
	if(channel == "children" && claim_target_to_delete)
		var/datum/doomed = claim_target_to_delete
		claim_target_to_delete = null
		qdel(doomed)
	if(channel == "children" && rich_target_to_unlink)
		var/datum/object_model/test_relation_publication_entity/doomed_rich = rich_target_to_unlink
		rich_target_to_unlink = null
		rich_claim_saw_provisional = om_has_link(src, /datum/object_model/test_publication_rich_relation, doomed_rich)
		om_unlink(src, /datum/object_model/test_publication_rich_relation, doomed_rich)
	if(channel == "children" && rich_winner_to_unlink_on_release)
		var/datum/object_model/test_relation_publication_entity/winner = rich_winner_to_unlink_on_release
		rich_winner_to_unlink_on_release = null
		om_unlink(src, /datum/object_model/test_publication_rich_relation, winner)
	if(channel == "children" && rich_target_to_relink)
		var/datum/object_model/test_relation_publication_entity/rebuilt_rich = rich_target_to_relink
		rich_target_to_relink = null
		om_unlink(src, /datum/object_model/test_publication_rich_relation, rebuilt_rich)
		om_link(src, /datum/object_model/test_publication_rich_relation, rebuilt_rich)
		if(unlink_rich_winner_on_provisional_release)
			rich_winner_to_unlink_on_release = rebuilt_rich
	if(channel == "children" && owned_target_to_relink)
		var/datum/object_model/test_relation_publication_entity/relinked = owned_target_to_relink
		owned_target_to_relink = null
		om_link(src, /datum/object_model/test_publication_owned_relation, relinked)
	if(channel == "children" && claim_competing_target)
		var/datum/object_model/test_relation_publication_entity/competitor = claim_competing_target
		claim_competing_target = null
		om_link(src, /datum/object_model/test_publication_owned_relation, competitor)
	if(channel != "relations" || !next_relation_action)
		return
	var/action = next_relation_action
	next_relation_action = null
	if(action == "unlink")
		om_unlink(src, /datum/object_model/test_publication_relation, relation_target)
	else if(action == "relink")
		om_link(src, /datum/object_model/test_publication_relation, relation_target)

/datum/object_model/test_publication_relation
	parent_type = /datum/object_model/relation
	from_type = /datum/object_model/test_relation_publication_entity
	to_type = /datum/object_model/test_relation_publication_entity
	source_single = TRUE

/datum/object_model/test_publication_relation/on_link(datum/source, datum/target)
	var/datum/object_model/test_relation_publication_entity/entity = source
	entity.relation_mirror = TRUE
	if(entity.link_hook_unlink)
		entity.link_hook_unlink = FALSE
		om_unlink(source, type, target)

/datum/object_model/test_publication_relation/on_unlink(datum/source, datum/target, reason)
	var/datum/object_model/test_relation_publication_entity/entity = source
	entity.relation_mirror = FALSE
	if(entity.unlink_hook_relink)
		entity.unlink_hook_relink = FALSE
		om_link(source, type, target)

/datum/object_model/test_publication_owned_relation
	parent_type = /datum/object_model/relation
	from_type = /datum/object_model/test_relation_publication_entity
	to_type = /datum/object_model/test_relation_publication_entity
	target_single = TRUE
	source_single = TRUE
	ownership = OM_REL_OWN_TARGET

/datum/object_model/test_publication_owned_relation/on_link(datum/source, datum/target)
	var/datum/object_model/test_relation_publication_entity/entity = source
	entity.relation_mirror = TRUE

/datum/object_model/test_publication_owned_relation/on_unlink(datum/source, datum/target, reason)
	var/datum/object_model/test_relation_publication_entity/entity = source
	entity.relation_mirror = FALSE

/datum/object_model/test_publication_rich_relation
	parent_type = /datum/object_model/relation
	from_type = /datum/object_model/test_relation_publication_entity
	to_type = /datum/object_model/test_relation_publication_entity
	rich = TRUE

/datum/object_model/test_publication_rich_relation/on_link(datum/source, datum/target)
	var/datum/object_model/test_relation_publication_entity/entity = source
	entity.relation_mirror = TRUE

/datum/object_model/test_publication_rich_relation/on_unlink(datum/source, datum/target, reason)
	var/datum/object_model/test_relation_publication_entity/entity = source
	entity.relation_mirror = FALSE

/datum/unit_test/om_lifetime_ownership
	needs_test_block = FALSE

/datum/unit_test/om_lifetime_ownership/Run()
	var/datum/object_model/test_lifetime_entity/root = new
	var/datum/object_model/test_lifetime_entity/child = new
	var/datum/object_model/test_lifetime_entity/grandchild = new
	TEST_ASSERT(om_claim(root, "children", child), "root claims child")
	TEST_ASSERT(om_claim(child, "children", grandchild), "child claims grandchild")
	TEST_ASSERT_EQUAL(om_owner(grandchild), child, "owner is visible")
	TEST_ASSERT(!om_claim(grandchild, "children", root), "ownership cycles are rejected")
	TEST_ASSERT_EQUAL(length(om_children(root, "children")), 1, "slot lists one child")
	TEST_ASSERT(om_release(grandchild), "release succeeds")
	TEST_ASSERT_NULL(om_owner(grandchild), "release clears ownership")
	qdel(root)
	TEST_ASSERT(QDELETED(child), "destroying an authority destroys its child")
	qdel(grandchild)

/datum/unit_test/om_lifetime_relations
	needs_test_block = FALSE

/datum/unit_test/om_lifetime_relations/Run()
	var/datum/object_model/test_lifetime_entity/source = new
	var/datum/object_model/test_lifetime_entity/first = new
	var/datum/object_model/test_lifetime_entity/second = new
	var/kind = /datum/object_model/test_relation
	TEST_ASSERT(om_link(source, kind, first), "first link succeeds")
	TEST_ASSERT(om_has_link(source, kind, first), "source indexes target")
	TEST_ASSERT_EQUAL(om_linked_to(first, kind)[1], source, "target indexes source")
	TEST_ASSERT(om_link(source, kind, second), "replacement link succeeds")
	TEST_ASSERT(!om_has_link(source, kind, first), "exclusive link replaces first target")
	TEST_ASSERT_EQUAL(source.unlinks, 1, "replacement invokes unlink hook once")
	TEST_ASSERT_EQUAL(source.last_reason, OM_REL_REPLACED, "replacement reason reaches hook")
	qdel(second)
	TEST_ASSERT(!om_has_link(source, kind, second), "destroyed endpoint unlinks")
	TEST_ASSERT_EQUAL(source.last_reason, OM_REL_DESTROYING, "destroy reason reaches survivor")
	TEST_ASSERT(!om_link(source, kind, second), "dying endpoint cannot be linked")
	qdel(source)
	qdel(first)

/datum/unit_test/om_lifetime_rich_and_slot_policy
	needs_test_block = FALSE

/datum/unit_test/om_lifetime_rich_and_slot_policy/Run()
	var/datum/object_model/test_declared_owner/owner = new
	var/datum/object_model/test_lifetime_entity/first = new
	var/datum/object_model/test_lifetime_entity/second = new
	TEST_ASSERT(om_claim(owner, "children", first), "declared slot accepts child")
	TEST_ASSERT(!om_claim(owner, "children", second), "declared slot enforces capacity")
	TEST_ASSERT(!om_claim(owner, "misspelled", second), "declared owner rejects an unknown slot")
	TEST_ASSERT(om_link(first, /datum/object_model/test_rich_relation, second), "rich relation links")
	var/datum/object_model/edge/edge = om_edge(first, /datum/object_model/test_rich_relation, second)
	TEST_ASSERT(edge && om_owner(edge) == first, "rich edge has one lifetime authority")
	TEST_ASSERT(om_unlink(first, /datum/object_model/test_rich_relation, second), "rich relation unlinks")
	TEST_ASSERT(QDELETED(edge), "unlink destroys rich edge")
	qdel(owner)
	TEST_ASSERT(QDELETED(first), "failed transfer takes declared delete fallback")
	qdel(second)

/datum/unit_test/om_lifetime_destroy_order
	needs_test_block = FALSE

/datum/unit_test/om_lifetime_destroy_order/Run()
	var/list/events = list()
	var/datum/object_model/test_order_entity/root = new
	root.events = events
	root.id = "root"
	var/datum/object_model/test_order_entity/child = new
	child.events = events
	child.id = "child"
	var/datum/object_model/test_order_entity/leaf = new
	leaf.events = events
	leaf.id = "leaf"
	TEST_ASSERT(om_claim(root, "children", child), "root owns child")
	TEST_ASSERT(om_claim(child, "children", leaf), "child owns leaf")
	qdel(root) // direct legacy qdel must enter the object-model bridge
	TEST_ASSERT_EQUAL(jointext(events, ","), "leaf,child,root", "direct qdel finalizes tracked children leaf first")
	TEST_ASSERT(QDELETED(child) && QDELETED(leaf), "all owned descendants are deleted")

/datum/unit_test/om_lifetime_destroy_reentrant
	needs_test_block = FALSE

/datum/unit_test/om_lifetime_destroy_reentrant/Run()
	var/list/events = list()
	var/datum/object_model/test_order_entity/root = new
	root.events = events
	root.id = "root"
	var/datum/object_model/test_order_entity/extra = new
	extra.events = events
	extra.id = "extra"
	TEST_ASSERT(om_link(root, /datum/object_model/test_reentrant_relation, extra), "link for reentrant destroy")
	TEST_ASSERT(om_destroy(root), "model destroy accepts root")
	TEST_ASSERT_EQUAL(jointext(events, ","), "root,extra", "hook-requested destroy drains after root transaction")
	TEST_ASSERT_EQUAL(extra.destroy_calls, 1, "duplicate hook requests delete once")
	TEST_ASSERT(!om_destroy(root), "destroy intent is idempotent")

/datum/object_model/test_dying_unlink_entity
	var/relation_changes = 0
	var/ownership_changes = 0
	var/unlinks = 0
	var/last_unlink_reason

/datum/object_model/test_dying_unlink_entity/om_cache_changed(channel)
	. = ..()
	if(channel == "relations")
		relation_changes++
	else if(channel == "children" || channel == "owner")
		ownership_changes++

/datum/object_model/test_dying_unlink_relation
	parent_type = /datum/object_model/relation
	from_type = /datum/object_model/test_dying_unlink_entity
	to_type = /datum/object_model/test_dying_unlink_entity

/datum/object_model/test_dying_unlink_relation/on_unlink(datum/source, datum/target, reason)
	var/datum/object_model/test_dying_unlink_entity/S = source
	S.unlinks++
	S.last_unlink_reason = reason

/datum/unit_test/om_dying_pair_unlink_skips_publication
	needs_test_block = FALSE

/datum/unit_test/om_dying_pair_unlink_skips_publication/Run()
	var/datum/object_model/test_dying_unlink_entity/root = new
	var/datum/object_model/test_dying_unlink_entity/source = new
	var/datum/object_model/test_dying_unlink_entity/target = new
	TEST_ASSERT(om_claim(root, "children", source), "root owns source")
	TEST_ASSERT(om_claim(root, "children", target), "root owns target")
	TEST_ASSERT(om_link(source, /datum/object_model/test_dying_unlink_relation, target), "source links target")
	var/source_relations = source.relation_changes
	var/target_relations = target.relation_changes
	var/root_ownership = root.ownership_changes
	var/source_ownership = source.ownership_changes
	var/target_ownership = target.ownership_changes
	qdel(root)
	TEST_ASSERT_EQUAL(source.unlinks, 1, "destroy invokes relation hook exactly once")
	TEST_ASSERT_EQUAL(source.last_unlink_reason, OM_REL_DESTROYING, "hook retains destroy reason")
	TEST_ASSERT_EQUAL(source.relation_changes, source_relations, "dying source skips obsolete relation notification")
	TEST_ASSERT_EQUAL(target.relation_changes, target_relations, "dying target skips obsolete relation notification")
	TEST_ASSERT_EQUAL(root.ownership_changes, root_ownership, "dying owner skips obsolete child notification")
	TEST_ASSERT_EQUAL(source.ownership_changes, source_ownership, "dying source skips obsolete owner notification")
	TEST_ASSERT_EQUAL(target.ownership_changes, target_ownership, "dying target skips obsolete owner notification")
	TEST_ASSERT(QDELETED(source) && QDELETED(target), "both children still cascade through destruction")

/datum/unit_test/om_live_peer_unlink_still_publishes
	needs_test_block = FALSE

/datum/unit_test/om_live_peer_unlink_still_publishes/Run()
	var/datum/object_model/test_dying_unlink_entity/source = new
	var/datum/object_model/test_dying_unlink_entity/target = new
	TEST_ASSERT(om_link(source, /datum/object_model/test_dying_unlink_relation, target), "live source links doomed target")
	var/relation_changes = source.relation_changes
	var/revision = om_revision(source)
	qdel(target)
	TEST_ASSERT_EQUAL(source.unlinks, 1, "target destruction invokes relation hook")
	TEST_ASSERT_EQUAL(source.last_unlink_reason, OM_REL_DESTROYING, "live peer hook retains destroy reason")
	TEST_ASSERT_EQUAL(source.relation_changes, relation_changes + 1, "live peer observes lost relation")
	TEST_ASSERT_EQUAL(om_revision(source), revision + 1, "live peer revision advances on lost relation")
	TEST_ASSERT(!om_has_link(source, /datum/object_model/test_dying_unlink_relation, target), "live peer has no stale edge")
	qdel(source)
/datum/unit_test/om_disposal_trunk_connection

/datum/unit_test/om_disposal_trunk_connection/Run()
	var/obj/owner = new()
	var/obj/other = new()
	var/turf/test_turf = test_floor()
	TEST_ASSERT_NOTNULL(test_turf, "disposal test needs a turf")
	var/obj/structure/disposalpipe/trunk/trunk = new(test_turf)
	var/datum/component/disposal_system_connection/connection = owner.AddComponent(/datum/component/disposal_system_connection)
	var/datum/component/disposal_system_connection/other_connection = other.AddComponent(/datum/component/disposal_system_connection)
	TEST_ASSERT_NOTNULL(connection, "disposal connection component was not created")
	TEST_ASSERT_NOTNULL(other_connection, "second disposal connection component was not created")
	SEND_SIGNAL(owner, COMSIG_DISPOSAL_LINK, trunk)
	TEST_ASSERT(om_has_link(connection, /datum/object_model/relation/disposal_trunk, trunk), "link signal did not establish relation")
	TEST_ASSERT(trunk.linked_owner() == owner, "trunk did not resolve its linked owner")
	SEND_SIGNAL(other, COMSIG_DISPOSAL_LINK, trunk)
	TEST_ASSERT(!other_connection.connected_trunk(), "second owner replaced occupied trunk")
	SEND_SIGNAL(owner, COMSIG_DISPOSAL_UNLINK)
	TEST_ASSERT(!trunk.linked_owner(), "unlink signal left a trunk owner")
	SEND_SIGNAL(other, COMSIG_DISPOSAL_LINK, trunk)
	TEST_ASSERT(trunk.linked_owner() == other, "trunk could not be reused after unlink")
	qdel(other)
	TEST_ASSERT(!trunk.linked_owner(), "owner destruction left a stale trunk connection")
	SEND_SIGNAL(owner, COMSIG_DISPOSAL_LINK, trunk)
	TEST_ASSERT(connection.connected_trunk() == trunk, "trunk did not relink after owner destruction")
	qdel(trunk)
	TEST_ASSERT(!connection.connected_trunk(), "trunk destruction left a stale owner connection")
	qdel(owner)

/datum/unit_test/om_redgate_partner_relation

/datum/unit_test/om_redgate_partner_relation/Run()
	var/turf/floor = test_floor()
	TEST_ASSERT_NOTNULL(floor, "redgate test needs a turf")
	var/obj/structure/redgate/first = new(floor)
	var/obj/structure/redgate/second = new(floor)
	TEST_ASSERT(om_link(first, /datum/object_model/relation/redgate_partner, second), "redgates should pair")
	TEST_ASSERT_EQUAL(first.partner(), second, "first redgate should see the second")
	TEST_ASSERT_EQUAL(second.partner(), first, "second redgate should see the first")
	TEST_ASSERT(first.density && second.density, "both paired redgates should be active")
	qdel(first)
	TEST_ASSERT_NULL(second.partner(), "deleting a redgate should unlink its partner")
	TEST_ASSERT(!second.density, "surviving redgate should deactivate")
	qdel(second)

/datum/unit_test/om_message_monitor_server_relation

/datum/unit_test/om_message_monitor_server_relation/Run()
	var/turf/floor = test_floor()
	TEST_ASSERT_NOTNULL(floor, "messaging relation test needs a turf")
	var/obj/machinery/computer/message_monitor/monitor = new(floor)
	var/obj/machinery/message_server/first = new(floor)
	var/obj/machinery/message_server/second = new(floor)
	TEST_ASSERT(monitor.set_linked_server(first), "monitor should link to first server")
	TEST_ASSERT(om_has_link(monitor, /datum/object_model/relation/message_monitor_server, first), "server link should be indexed")
	TEST_ASSERT(monitor.set_linked_server(second), "monitor should transfer to second server")
	TEST_ASSERT(!om_has_link(monitor, /datum/object_model/relation/message_monitor_server, first), "old server link should be gone")
	qdel(second)
	TEST_ASSERT_NULL(monitor.linkedServer, "server deletion should clear monitor reference")
	qdel(monitor)
	qdel(first)

/datum/unit_test/om_pod_mass_driver_relation

/datum/unit_test/om_pod_mass_driver_relation/Run()
	var/turf/floor = test_floor()
	TEST_ASSERT_NOTNULL(floor, "pod driver test needs a turf")
	var/obj/machinery/computer/pod/console = new(floor)
	var/obj/machinery/mass_driver/first = new(floor)
	var/obj/machinery/mass_driver/second = new(floor)
	TEST_ASSERT(console.set_connected_driver(first), "console should link to first driver")
	TEST_ASSERT(om_has_link(console, /datum/object_model/relation/pod_mass_driver, first), "driver link should be indexed")
	TEST_ASSERT(console.set_connected_driver(second), "console should transfer to second driver")
	TEST_ASSERT(!om_has_link(console, /datum/object_model/relation/pod_mass_driver, first), "old driver link should be removed")
	qdel(second)
	TEST_ASSERT_NULL(console.connected, "driver deletion should clear console reference")
	qdel(console)
	qdel(first)

/datum/unit_test/om_cloning_console_pod_relation

/datum/unit_test/om_cloning_console_pod_relation/Run()
	var/turf/floor = test_floor()
	TEST_ASSERT_NOTNULL(floor, "cloning relation test needs a turf")
	var/obj/machinery/computer/cloning/console = new(floor)
	var/obj/machinery/clonepod/first = new(floor)
	var/obj/machinery/clonepod/second = new(floor)
	TEST_ASSERT(om_link(console, /datum/object_model/relation/cloning_console_pod, first), "console should link first pod")
	TEST_ASSERT(om_link(console, /datum/object_model/relation/cloning_console_pod, second), "console should link second pod")
	TEST_ASSERT_EQUAL(length(console.linked_pods()), 2, "console should list both pods")
	TEST_ASSERT_EQUAL(first.connected_console(), console, "pod should resolve its console")
	console.selected_pod = first
	qdel(first)
	TEST_ASSERT_NULL(console.selected_pod, "deleted selected pod should clear selection")
	TEST_ASSERT_EQUAL(length(console.linked_pods()), 1, "deleted pod should leave relation index")
	qdel(console)
	TEST_ASSERT_NULL(second.connected_console(), "console deletion should unlink surviving pod")
	qdel(second)

/datum/unit_test/om_relation_reentrant_replacement
	needs_test_block = FALSE

/datum/unit_test/om_replace_related_preserves_old
	needs_test_block = FALSE

/datum/unit_test/om_replace_related_preserves_old/Run()
	var/datum/object_model/test_lifetime_entity/source = new
	var/datum/object_model/test_lifetime_entity/old_target = new
	var/datum/object_model/test_lifetime_entity/new_target = new
	var/datum/invalid_target = new
	var/kind = /datum/object_model/test_source_single_relation
	TEST_ASSERT(om_replace_related(source, kind, old_target), "initial replacement should link")
	TEST_ASSERT(!om_replace_related(source, kind, invalid_target), "invalid replacement should fail")
	TEST_ASSERT(om_has_link(source, kind, old_target), "failed replacement removed the old target")
	TEST_ASSERT(om_replace_related(source, kind, new_target), "valid replacement should link")
	TEST_ASSERT(!om_has_link(source, kind, old_target) && om_has_link(source, kind, new_target), "replacement left two targets")
	var/datum/object_model/test_lifetime_entity/doomed = new
	doomed.delete_on_replacement_link = TRUE
	TEST_ASSERT(!om_replace_related(source, kind, doomed), "replacement should fail when its link hook deletes the candidate")
	TEST_ASSERT(om_has_link(source, kind, new_target), "failed commit should restore the previous live target")
	TEST_ASSERT(om_replace_related(source, kind, null), "null replacement should unlink")
	TEST_ASSERT_NULL(om_first_linked(source, kind), "null replacement left a target")
	qdel(source)
	qdel(old_target)
	qdel(new_target)
	qdel(invalid_target)

/datum/unit_test/om_relation_reentrant_replacement/Run()
	var/datum/object_model/test_lifetime_entity/first = new
	var/datum/object_model/test_lifetime_entity/replacement = new
	var/datum/object_model/test_lifetime_entity/rebound = new
	var/datum/object_model/test_lifetime_entity/target = new
	var/kind = /datum/object_model/test_replacement_relation
	var/datum/object_model/test_replacement_relation/definition = om_relation_def(kind)
	TEST_ASSERT(om_link(first, kind, target), "initial single-target relation should link")
	definition.rebind_source = rebound
	TEST_ASSERT(!om_link(replacement, kind, target), "replacement should fail when unlink hook rebinds target")
	TEST_ASSERT_EQUAL(length(om_linked_to(target, kind)), 1, "target-single relation should keep one source")
	TEST_ASSERT(om_has_link(rebound, kind, target), "reentrant hook's link should remain")
	TEST_ASSERT(!om_has_link(replacement, kind, target), "outer replacement must not add another source")
	qdel(first)
	qdel(replacement)
	qdel(rebound)
	qdel(target)

/datum/unit_test/om_relation_link_hook_deletes_endpoint
	needs_test_block = FALSE

/datum/unit_test/om_relation_link_hook_deletes_endpoint/Run()
	var/datum/object_model/test_lifetime_entity/source = new
	var/datum/object_model/test_lifetime_entity/target = new
	var/kind = /datum/object_model/test_link_hook_deletes_target
	TEST_ASSERT(!om_link(source, kind, target), "link reports failure when its hook deletes an endpoint")
	TEST_ASSERT(QDELETED(target), "link hook deleted its target")
	TEST_ASSERT_EQUAL(length(om_linked(source, kind)), 0, "deleted target leaves no relation")
	qdel(source)

/datum/unit_test/om_claim_rechecks_after_release
	needs_test_block = FALSE

/datum/unit_test/om_claim_rechecks_after_release/Run()
	var/datum/object_model/test_release_reentry_owner/old_owner = new
	var/datum/object_model/test_lifetime_entity/new_owner = new
	var/datum/object_model/test_lifetime_entity/child = new
	TEST_ASSERT(om_claim(old_owner, "children", child), "initial owner claims child")
	old_owner.destination_to_delete = new_owner
	TEST_ASSERT(!om_claim(new_owner, "children", child), "claim fails when releasing old owner deletes destination")
	TEST_ASSERT(QDELETED(new_owner), "release callback deleted destination")
	TEST_ASSERT_NULL(om_owner(child), "failed transfer leaves child unowned")
	qdel(old_owner)
	qdel(child)

/datum/unit_test/om_claim_same_destination_reentry
	needs_test_block = FALSE

/datum/unit_test/om_claim_same_destination_reentry/Run()
	var/datum/object_model/test_release_reentry_owner/old_owner = new
	var/datum/object_model/test_lifetime_entity/new_owner = new
	var/datum/object_model/test_lifetime_entity/child = new
	TEST_ASSERT(om_claim(old_owner, "children", child), "Initial owner claims child")
	old_owner.destination_to_claim = new_owner
	old_owner.child_to_claim = child
	TEST_ASSERT(om_claim(new_owner, "children", child), "A reentrant claim for the same destination counts as success")
	TEST_ASSERT_EQUAL(om_owner(child), new_owner, "Child has the requested owner")
	TEST_ASSERT_EQUAL(om_owner_slot(child), "children", "Child has the requested slot")
	qdel(old_owner)
	qdel(new_owner)

/datum/unit_test/om_relation_link_publication_reentry
	needs_test_block = FALSE

/datum/unit_test/om_relation_link_publication_reentry/Run()
	var/datum/object_model/test_relation_publication_entity/source = new
	var/datum/object_model/test_relation_publication_entity/target = new
	source.relation_target = target
	source.next_relation_action = "unlink"
	TEST_ASSERT(!om_link(source, /datum/object_model/test_publication_relation, target), "A publication callback may unlink the newly stored edge")
	TEST_ASSERT(!om_has_link(source, /datum/object_model/test_publication_relation, target), "The callback removed the relation")
	TEST_ASSERT(!source.relation_mirror, "The link hook must not restore a mirror for an absent relation")
	qdel(source)
	qdel(target)

/datum/unit_test/om_relation_unlink_publication_reentry
	needs_test_block = FALSE

/datum/unit_test/om_relation_unlink_publication_reentry/Run()
	var/datum/object_model/test_relation_publication_entity/source = new
	var/datum/object_model/test_relation_publication_entity/target = new
	source.relation_target = target
	TEST_ASSERT(om_link(source, /datum/object_model/test_publication_relation, target), "Initial relation links")
	source.next_relation_action = "relink"
	TEST_ASSERT(om_unlink(source, /datum/object_model/test_publication_relation, target), "The outer unlink completes")
	TEST_ASSERT(om_has_link(source, /datum/object_model/test_publication_relation, target), "The callback reinstalled the relation")
	TEST_ASSERT(source.relation_mirror, "The old unlink hook must not clear the new relation's mirror")
	qdel(source)
	qdel(target)

/datum/unit_test/om_relation_link_hook_unlinks_before_publication
	needs_test_block = FALSE

/datum/unit_test/om_relation_link_hook_unlinks_before_publication/Run()
	var/datum/object_model/test_relation_publication_entity/source = new
	var/datum/object_model/test_relation_publication_entity/target = new
	source.link_hook_unlink = TRUE
	TEST_ASSERT(!om_link(source, /datum/object_model/test_publication_relation, target), "Link reports an edge removed by its own hook")
	TEST_ASSERT(!om_has_link(source, /datum/object_model/test_publication_relation, target), "Hook removed the edge")
	TEST_ASSERT(!source.relation_mirror, "Hook cleanup removed the mirror")
	TEST_ASSERT_EQUAL(source.relation_notifications, 1, "Only the surviving unlink publishes a relation change")
	qdel(source)
	qdel(target)

/datum/unit_test/om_relation_unlink_hook_relinks_before_publication
	needs_test_block = FALSE

/datum/unit_test/om_relation_unlink_hook_relinks_before_publication/Run()
	var/datum/object_model/test_relation_publication_entity/source = new
	var/datum/object_model/test_relation_publication_entity/target = new
	TEST_ASSERT(om_link(source, /datum/object_model/test_publication_relation, target), "Initial edge links")
	var/before = source.relation_notifications
	source.unlink_hook_relink = TRUE
	TEST_ASSERT(om_unlink(source, /datum/object_model/test_publication_relation, target), "Outer unlink completes")
	TEST_ASSERT(om_has_link(source, /datum/object_model/test_publication_relation, target), "Hook reinstalled the edge")
	TEST_ASSERT(source.relation_mirror, "The new edge retains its mirror")
	TEST_ASSERT_EQUAL(source.relation_notifications, before + 1, "Only the surviving re-link publishes a relation change")
	qdel(source)
	qdel(target)

/datum/unit_test/om_relation_claim_publication_reentry
	needs_test_block = FALSE

/datum/unit_test/om_relation_claim_publication_reentry/Run()
	var/datum/object_model/test_relation_publication_entity/source = new
	var/datum/object_model/test_relation_publication_entity/target = new
	source.claim_target_to_delete = target
	TEST_ASSERT(!om_link(source, /datum/object_model/test_publication_owned_relation, target), "A claim callback deleting its endpoint must abort the link")
	TEST_ASSERT(QDELETED(target), "The ownership callback deleted the target")
	TEST_ASSERT(!length(om_linked(source, /datum/object_model/test_publication_owned_relation)), "An aborted ownership link must not leave an edge")
	qdel(source)

/datum/unit_test/om_relation_rich_claim_reentry
	needs_test_block = FALSE

/datum/unit_test/om_relation_rich_claim_reentry/Run()
	var/datum/object_model/test_relation_publication_entity/source = new
	var/datum/object_model/test_relation_publication_entity/target = new
	source.rich_target_to_unlink = target
	TEST_ASSERT(om_link(source, /datum/object_model/test_publication_rich_relation, target), "A rich edge can commit after its claim callback")
	TEST_ASSERT(!source.rich_claim_saw_provisional, "Claim callbacks must not see a provisional rich relation")
	TEST_ASSERT(om_has_link(source, /datum/object_model/test_publication_rich_relation, target), "The rich edge commits after its claim")
	TEST_ASSERT_NOTNULL(om_edge(source, /datum/object_model/test_publication_rich_relation, target), "Committed rich edge has metadata")
	TEST_ASSERT_EQUAL(length(om_children(source, "om:edges")), 1, "Only the committed edge is owned")
	TEST_ASSERT(source.relation_mirror, "Committed rich edge has its mirror")
	qdel(source)
	qdel(target)

/datum/unit_test/om_relation_rich_claim_same_pair_reentry
	needs_test_block = FALSE

/datum/unit_test/om_relation_rich_claim_same_pair_reentry/Run()
	var/datum/object_model/test_relation_publication_entity/source = new
	var/datum/object_model/test_relation_publication_entity/target = new
	source.rich_target_to_relink = target
	TEST_ASSERT(om_link(source, /datum/object_model/test_publication_rich_relation, target), "Outer link reports the winning same-pair edge")
	TEST_ASSERT(om_has_link(source, /datum/object_model/test_publication_rich_relation, target), "Nested rich edge survives")
	TEST_ASSERT_EQUAL(length(om_children(source, "om:edges")), 1, "Discarded provisional edge releases ownership")
	TEST_ASSERT(source.relation_mirror, "Winning rich edge retains its mirror")
	qdel(source)
	qdel(target)

/datum/unit_test/om_relation_rich_cleanup_changes_winner
	needs_test_block = FALSE

/datum/unit_test/om_relation_rich_cleanup_changes_winner/Run()
	var/datum/object_model/test_relation_publication_entity/source = new
	var/datum/object_model/test_relation_publication_entity/target = new
	source.rich_target_to_relink = target
	source.unlink_rich_winner_on_provisional_release = TRUE
	TEST_ASSERT(!om_link(source, /datum/object_model/test_publication_rich_relation, target), "Return value follows the edge state after provisional cleanup")
	TEST_ASSERT(!om_has_link(source, /datum/object_model/test_publication_rich_relation, target), "Cleanup callback removed the nested winner")
	TEST_ASSERT(!source.relation_mirror, "Removing the winner cleared its mirror")
	TEST_ASSERT(!length(om_children(source, "om:edges")), "Both rich edge datums were released")
	qdel(source)
	qdel(target)

/datum/unit_test/om_relation_owned_unlink_release_reentry
	needs_test_block = FALSE

/datum/unit_test/om_relation_owned_unlink_release_reentry/Run()
	var/datum/object_model/test_relation_publication_entity/source = new
	var/datum/object_model/test_relation_publication_entity/target = new
	TEST_ASSERT(om_link(source, /datum/object_model/test_publication_owned_relation, target), "Initial owning relation links")
	source.owned_target_to_relink = target
	TEST_ASSERT(om_unlink(source, /datum/object_model/test_publication_owned_relation, target), "Initial owning relation unlinks")
	TEST_ASSERT(om_has_link(source, /datum/object_model/test_publication_owned_relation, target), "Ownership-release callback relinked the edge")
	TEST_ASSERT_EQUAL(om_owner(target), source, "Re-linked target keeps ownership")
	TEST_ASSERT(source.relation_mirror, "Old unlink cleanup must not clear the new edge mirror")
	qdel(source)
	qdel(target)

/datum/unit_test/om_relation_claim_competing_edge
	needs_test_block = FALSE

/datum/unit_test/om_relation_claim_competing_edge/Run()
	var/datum/object_model/test_relation_publication_entity/source = new
	var/datum/object_model/test_relation_publication_entity/original = new
	var/datum/object_model/test_relation_publication_entity/competitor = new
	source.claim_competing_target = competitor
	TEST_ASSERT(!om_link(source, /datum/object_model/test_publication_owned_relation, original), "Outer claim yields to a competing edge installed by its callback")
	TEST_ASSERT(!om_has_link(source, /datum/object_model/test_publication_owned_relation, original), "Original edge did not survive")
	TEST_ASSERT(om_has_link(source, /datum/object_model/test_publication_owned_relation, competitor), "Winning edge survived")
	TEST_ASSERT_EQUAL(om_owner(competitor), source, "Winning edge retained its ownership claim")
	TEST_ASSERT_NULL(om_owner(original), "Failed edge released its unused ownership claim")
	TEST_ASSERT(source.relation_mirror, "Winning edge retained its mirror")
	qdel(source)
	qdel(original)
	qdel(competitor)

/datum/object_model/test_required_partner
	var/activations = 0
	var/deactivations = 0
	var/events_seen = 0

/datum/object_model/relation/test_required_partner
	from_type = /datum/object_model/test_required_partner
	to_type = /datum
	source_single = TRUE

/datum/object_model/event/test_required_partner_ping

/datum/object_model/behaviour/test_required_partner
	events = list(/datum/object_model/event/test_required_partner_ping)

/datum/object_model/behaviour/test_required_partner/on_activate(datum/source, list/config)
	var/datum/object_model/test_required_partner/entity = source
	entity.activations++

/datum/object_model/behaviour/test_required_partner/on_deactivate(datum/source, list/config, reason)
	var/datum/object_model/test_required_partner/entity = source
	entity.deactivations++

/datum/object_model/behaviour/test_required_partner/on_event(datum/source, datum/object_model/event/E, a, b, c, d, list/config)
	var/datum/object_model/test_required_partner/entity = source
	entity.events_seen++

/datum/object_model/declaration/test_required_partner
	target_type = /datum/object_model/test_required_partner

/datum/object_model/declaration/test_required_partner/build(datum/object_model/archetype/A)
	A.relation(/datum/object_model/relation/test_required_partner, TRUE)
	A.add(/datum/object_model/behaviour/test_required_partner)

/datum/unit_test/om_required_relation_gates_behaviour
	needs_test_block = FALSE

/datum/unit_test/om_required_relation_gates_behaviour/Run()
	var/datum/object_model/test_required_partner/entity = new
	var/datum/first = new
	var/datum/second = new
	var/datum/object_model/behaviour_runtime/R = om_behaviour_start(entity)
	var/behaviour_path = /datum/object_model/behaviour/test_required_partner
	var/relation_path = /datum/object_model/relation/test_required_partner
	TEST_ASSERT_NOTNULL(R, "Required-relation archetype starts")
	TEST_ASSERT(!R.active[behaviour_path], "Missing required partner keeps behaviour dormant")
	om_emit(entity, /datum/object_model/event/test_required_partner_ping)
	TEST_ASSERT_EQUAL(entity.events_seen, 0, "Missing partner gates event delivery")
	TEST_ASSERT(om_link(entity, relation_path, first), "Required partner links")
	TEST_ASSERT(R.active[behaviour_path], "Link activates behaviour")
	TEST_ASSERT_EQUAL(entity.activations, 1, "Link activates exactly once")
	om_emit(entity, /datum/object_model/event/test_required_partner_ping)
	TEST_ASSERT_EQUAL(entity.events_seen, 1, "Linked behaviour receives event")
	TEST_ASSERT(om_unlink(entity, relation_path, first), "Required partner unlinks")
	TEST_ASSERT(!R.active[behaviour_path], "Unlink deactivates behaviour")
	TEST_ASSERT_EQUAL(entity.deactivations, 1, "Unlink deactivates exactly once")
	om_emit(entity, /datum/object_model/event/test_required_partner_ping)
	TEST_ASSERT_EQUAL(entity.events_seen, 1, "Unlinked behaviour does not receive event")
	TEST_ASSERT(om_link(entity, relation_path, second), "Replacement partner links")
	TEST_ASSERT_EQUAL(entity.activations, 2, "New partner reactivates behaviour")
	qdel(second)
	TEST_ASSERT(!R.active[behaviour_path], "Partner deletion deactivates behaviour")
	qdel(first)
	qdel(entity)
