// A slot's on_link()/on_unlink() hooks run from the holder's ledger and nowhere else: there is no relation edge to carry them
// (S4 step 5). Each membership ends exactly once, with both ends still whole.

/// Holder whose slot spills its contents on destroy.
/obj/slot_hook_fixture/rack
	name = "slot hook rack"

/// Holder whose slot keeps its contents with it on destroy.
/obj/slot_hook_fixture/keeper
	name = "slot hook keeper"

/obj/item/slot_hook_fixture
	name = "slot hook item"

/datum/relation_definition/slot/hook_log
	abstract_type = /datum/relation_definition/slot/hook_log
	/// "link"/"unlink", whether the thing was still in the holder, and whether it was already QDELETED, in the order they happened.
	var/list/log

/datum/relation_definition/slot/hook_log/on_link(atom/movable/source, atom/target)
	LAZYADD(log, "link in=[source.loc == target ? 1 : 0] deleted=[QDELETED(source) ? 1 : 0]")

/datum/relation_definition/slot/hook_log/on_unlink(atom/movable/source, atom/target)
	LAZYADD(log, "unlink in=[source.loc == target ? 1 : 0] deleted=[QDELETED(source) ? 1 : 0] holder_deleted=[QDELETED(target) ? 1 : 0]")

/datum/relation_definition/slot/hook_log/rack
	holder = /obj/slot_hook_fixture/rack
	slot_id = "hook_rack"
	name = "hook rack"
	is_default = TRUE
	drop_policy = SLOT_DROP_SPILL

/datum/relation_definition/slot/hook_log/keeper
	holder = /obj/slot_hook_fixture/keeper
	slot_id = "hook_keeper"
	name = "hook keeper"
	is_default = TRUE
	drop_policy = SLOT_DROP_HOLDER

/datum/unit_test/dq_slot_hooks
	abstract_type = /datum/unit_test/dq_slot_hooks

/datum/unit_test/dq_slot_hooks/proc/slot_log(path)
	var/datum/relation_definition/slot/hook_log/def = dq_slot_def(path)
	return def.log

/datum/unit_test/dq_slot_hooks/proc/reset_log(path)
	var/datum/relation_definition/slot/hook_log/def = dq_slot_def(path)
	def.log = null

/// Going in runs on_link and coming out runs on_unlink, once each, with the thing in the holder for the link and out of it for the unlink.
/datum/unit_test/dq_slot_hooks/enter_and_leave

/datum/unit_test/dq_slot_hooks/enter_and_leave/Run()
	reset_log(/datum/relation_definition/slot/hook_log/rack)
	var/turf/T = test_floor()
	var/obj/slot_hook_fixture/rack/rack = allocate(/obj/slot_hook_fixture/rack, T)
	var/obj/item/slot_hook_fixture/thing = allocate(/obj/item/slot_hook_fixture, T)
	TEST_ASSERT(move_into(rack, "hook_rack", thing), "the item goes into the slot")
	var/list/log = slot_log(/datum/relation_definition/slot/hook_log/rack)
	TEST_ASSERT_EQUAL(length(log), 1, "entering ran on_link once")
	TEST_ASSERT_EQUAL(log[1], "link in=1 deleted=0", "on_link saw the item inside its holder")
	thing.forceMove(T)
	log = slot_log(/datum/relation_definition/slot/hook_log/rack)
	TEST_ASSERT_EQUAL(length(log), 2, "leaving ran on_unlink once")
	TEST_ASSERT_EQUAL(log[2], "unlink in=0 deleted=0 holder_deleted=0", "on_unlink saw the item out of its holder")

/// A deleted item ends its membership in the destroy transaction's links phase, while it is still inside its holder: once, not again when it leaves for nullspace.
/datum/unit_test/dq_slot_hooks/thing_destroyed_in_slot

/datum/unit_test/dq_slot_hooks/thing_destroyed_in_slot/Run()
	reset_log(/datum/relation_definition/slot/hook_log/rack)
	var/turf/T = test_floor()
	var/obj/slot_hook_fixture/rack/rack = allocate(/obj/slot_hook_fixture/rack, T)
	var/obj/item/slot_hook_fixture/thing = allocate(/obj/item/slot_hook_fixture, T)
	TEST_ASSERT(move_into(rack, "hook_rack", thing), "the item goes into the slot")
	qdel(thing)
	TEST_ASSERT(QDELETED(thing), "the item is deleted")
	var/list/log = slot_log(/datum/relation_definition/slot/hook_log/rack)
	TEST_ASSERT_EQUAL(length(log), 2, "link and one unlink, no second unlink from the late move to nullspace")
	TEST_ASSERT_EQUAL(log[2], "unlink in=1 deleted=1 holder_deleted=0", "on_unlink ran in the links phase: the item still inside, already marked deleted")
	TEST_ASSERT_EQUAL(length(rack.contents), 0, "the holder no longer holds it")

/// A holder that spills its contents unlinks each of them in the contents phase, alive, once.
/datum/unit_test/dq_slot_hooks/holder_destroyed_spills

/datum/unit_test/dq_slot_hooks/holder_destroyed_spills/Run()
	reset_log(/datum/relation_definition/slot/hook_log/rack)
	var/turf/T = test_floor()
	var/obj/slot_hook_fixture/rack/rack = allocate(/obj/slot_hook_fixture/rack, T)
	var/obj/item/slot_hook_fixture/thing = allocate(/obj/item/slot_hook_fixture, T)
	TEST_ASSERT(move_into(rack, "hook_rack", thing), "the item goes into the slot")
	qdel(rack)
	TEST_ASSERT(QDELETED(rack), "the holder is deleted")
	var/list/log = slot_log(/datum/relation_definition/slot/hook_log/rack)
	TEST_ASSERT_EQUAL(length(log), 2, "link and one unlink")
	TEST_ASSERT(!QDELETED(thing), "the spilled item survives")

/// A holder that keeps its contents ends their memberships in its own links phase, with the holder still whole; the contents deleted after that do not unlink again.
/datum/unit_test/dq_slot_hooks/holder_destroyed_keeps

/datum/unit_test/dq_slot_hooks/holder_destroyed_keeps/Run()
	reset_log(/datum/relation_definition/slot/hook_log/keeper)
	var/turf/T = test_floor()
	var/obj/slot_hook_fixture/keeper/keeper = allocate(/obj/slot_hook_fixture/keeper, T)
	var/obj/item/slot_hook_fixture/thing = allocate(/obj/item/slot_hook_fixture, T)
	TEST_ASSERT(move_into(keeper, "hook_keeper", thing), "the item goes into the slot")
	qdel(keeper)
	TEST_ASSERT(QDELETED(keeper), "the holder is deleted")
	var/list/log = slot_log(/datum/relation_definition/slot/hook_log/keeper)
	TEST_ASSERT_EQUAL(length(log), 2, "link and one unlink")
	TEST_ASSERT_EQUAL(log[2], "unlink in=1 deleted=0 holder_deleted=1", "the kept item was unlinked in the holder's links phase, inside it")
