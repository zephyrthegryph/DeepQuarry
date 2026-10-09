// Object pools and their POOL_RESET declarations (doc/rewrite/ownership.md,
// code/datums/lifecycle/pool.dm).

/// A pooled type used only by these tests.
/datum/pool_test_item
	var/datum/held
	var/count = 3
	var/keep = "kept"

POOL_DECLARE(/datum/pool_test_item)
/datum/pool_test_item/ownership()
	. = ..()
	. += owns(nameof(held), policy = OWN_NONE, pool_reset = TRUE)
	. += owns(nameof(count), policy = OWN_NONE, pool_reset = TRUE)

/datum/pool_test_item/proc/touch()
	POOL_ASSERT_LIVE(src)
	return TRUE

/datum/unit_test/dq_pool
	abstract_type = /datum/unit_test/dq_pool

/// Take, release and take again: the same object comes back, its transient
/// fields reset from the declaration and its other fields left alone.
/datum/unit_test/dq_pool/recycle

/datum/unit_test/dq_pool/recycle/Run()
	var/was_poison = pool_set_poison(FALSE)
	var/datum/pool_test_item/item = pool_take(/datum/pool_test_item)
	TEST_ASSERT(istype(item), "pool_take() should hand out the pooled type")
	TEST_ASSERT_EQUAL(item.pool_state, POOL_STATE_TAKEN, "a taken object is marked taken")
	var/datum/other = new /datum
	rel_set(item, nameof(item.held), other)
	item.count = 9
	item.keep = "changed"
	item.release()
	TEST_ASSERT_EQUAL(item.pool_state, POOL_STATE_FREE, "a released object waits in its pool")
	TEST_ASSERT_NULL(item.held, "release() clears a POOL_RESET reference")
	TEST_ASSERT_EQUAL(item.count, 3, "release() resets a POOL_RESET scalar to its initial value")
	TEST_ASSERT_EQUAL(item.keep, "changed", "release() leaves undeclared fields alone")
	var/datum/pool_test_item/again = pool_take(/datum/pool_test_item)
	TEST_ASSERT(again == item, "a released object is reused")
	again.release()
	qdel(other)
	pool_set_poison(was_poison)

/// Releasing twice crashes and is counted.
/datum/unit_test/dq_pool/double_release

/datum/unit_test/dq_pool/double_release/Run()
	var/was_poison = pool_set_poison(FALSE)
	var/datum/pool_test_item/item = pool_take(/datum/pool_test_item)
	item.release()
	var/datum/object_pool/pool = GLOB.object_pools[/datum/pool_test_item]
	var/before = pool.double_releases
	var/crashed = FALSE
	try
		pool_release(item)
	catch
		crashed = TRUE
	TEST_ASSERT(crashed, "a second release should crash")
	TEST_ASSERT_EQUAL(pool.double_releases, before + 1, "a double release is counted")
	pool_set_poison(was_poison)

/// With poisoning on, a released object is never handed out again, and using
/// it crashes.
/datum/unit_test/dq_pool/poison

/datum/unit_test/dq_pool/poison/Run()
	var/was_poison = pool_set_poison(TRUE)
	var/datum/pool_test_item/item = pool_take(/datum/pool_test_item)
	TEST_ASSERT(item.touch(), "a taken object is live")
	item.release()
	TEST_ASSERT_EQUAL(item.pool_state, POOL_STATE_POISONED, "a released object is poisoned")
	var/crashed = FALSE
	try
		item.touch()
	catch
		crashed = TRUE
	TEST_ASSERT(crashed, "using a poisoned object should crash")
	var/datum/pool_test_item/fresh = pool_take(/datum/pool_test_item)
	TEST_ASSERT(fresh != item, "a poisoned object is never handed out again")
	pool_set_poison(FALSE)
	fresh.release()
	pool_set_poison(was_poison)

/// Pooled objects refuse a normal qdel.
/datum/unit_test/dq_pool/refuses_qdel

/datum/unit_test/dq_pool/refuses_qdel/Run()
	var/was_poison = pool_set_poison(FALSE)
	var/datum/pool_test_item/item = pool_take(/datum/pool_test_item)
	item.release()
	var/datum/object_pool/pool = GLOB.object_pools[/datum/pool_test_item]
	var/before = pool.refused_qdels
	qdel(item)
	TEST_ASSERT_EQUAL(pool.refused_qdels, before + 1, "the refused qdel is counted")
	var/datum/pool_test_item/again = pool_take(/datum/pool_test_item)
	TEST_ASSERT(again == item, "a refused qdel leaves the object in its pool")
	again.release()
	pool_set_poison(was_poison)

/// Pool stats appear in scheduler_diagnostics().
/datum/unit_test/dq_pool/diagnostics

/datum/unit_test/dq_pool/diagnostics/Run()
	var/datum/pool_test_item/item = pool_take(/datum/pool_test_item)
	item.release()
	var/list/snapshot = scheduler_diagnostics()
	var/list/pools = snapshot["pools"]
	TEST_ASSERT(islist(pools), "scheduler_diagnostics() reports pools")
	var/list/row = pools["[/datum/pool_test_item]"]
	TEST_ASSERT(islist(row), "each pooled type has a row")
	TEST_ASSERT(row["taken"] >= 1, "the row counts takes")
	TEST_ASSERT(row["released"] >= 1, "the row counts releases")

/// The damage packet runs on the generic pool; total() returns the sum.
/datum/unit_test/dq_pool/damage_packet

/datum/unit_test/dq_pool/damage_packet/Run()
	var/was_poison = pool_set_poison(FALSE)
	var/datum/damage_packet/probe = new
	var/list/plan = pool_reset_plan(probe)
	for(var/name in list("source", "attacker", "weapon"))
		TEST_ASSERT(name in plan, "damage packet [name] is reset on release")
	TEST_ASSERT_EQUAL(plan["amounts"], POOL_RESET_LIST, "the amounts list is kept and emptied")
	var/datum/other = new /datum
	var/datum/damage_packet/packet = damage_packet(other, other, other, BP_TORSO, DAMAGE_PACKET_SILENT, 7, NORTH)
	packet.add(DAMAGE_BLUNT, 4)
	packet.add(DAMAGE_THERMAL, 6)
	TEST_ASSERT_EQUAL(packet.total(), 10, "total() returns the sum of the kinds")
	packet.release()
	TEST_ASSERT_NULL(packet.source, "release clears source")
	TEST_ASSERT_NULL(packet.attacker, "release clears attacker")
	TEST_ASSERT_NULL(packet.weapon, "release clears weapon")
	TEST_ASSERT_EQUAL(packet.penetration, 0, "release resets penetration")
	TEST_ASSERT_EQUAL(packet.direction, 0, "release resets direction")
	var/datum/damage_packet/again = damage_packet()
	TEST_ASSERT(again == packet, "the packet is recycled")
	TEST_ASSERT_EQUAL(again.total(), 0, "a recycled packet comes back empty")
	again.release()
	qdel(other)
	qdel(probe, TRUE)
	pool_set_poison(was_poison)
