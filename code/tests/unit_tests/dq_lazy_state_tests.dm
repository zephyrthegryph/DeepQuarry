// Lazy owned state (owns_one(lazy = TRUE), code/engine/declare/lazy_state.dm): rarely used state is a small datum the holder owns, made on its first write.

/// The state datum: one tracked number a draw reads.
/datum/dq_lazy_burn
	var/fuel = 0

/// A drawn fixture holding the state lazily.
/obj/dq_lazy_lamp
	icon = 'icons/obj/lighting.dmi'
	icon_state = "lamp0"
	var/datum/dq_lazy_burn/burn

CAPABILITIES(/obj/dq_lazy_lamp)
	owns_one(nameof(burn), /datum/dq_lazy_burn, lazy = TRUE)

/obj/dq_lazy_lamp/draw(datum/look/look)
	..()
	look.state(burn?.fuel > 0 ? "lamp1" : "lamp0")

/// A read allocates nothing; the first write makes the datum once, owned by the holder; later writes reuse it.
/datum/unit_test/dq_lazy_state_made_on_first_write

/datum/unit_test/dq_lazy_state_made_on_first_write/Run()
	var/obj/dq_lazy_lamp/L = allocate(/obj/dq_lazy_lamp, test_floor())
	var/made = GLOB.lazy_states_made
	set_global("lazy_states_made", made) // the counter moves in this test; teardown restores it
	TEST_ASSERT_NULL(L.burn, "a fresh holder has no state datum")
	TEST_ASSERT_EQUAL(L.burn?.fuel, null, "a read of an unmade state is null")
	TEST_ASSERT_EQUAL(GLOB.lazy_states_made, made, "a read made nothing")
	var/datum/dq_lazy_burn/S = burn_of(L)
	TEST_ASSERT_NOTNULL(S, "burn_of() makes the state")
	TEST_ASSERT_EQUAL(L.burn, S, "the holder's var names it")
	TEST_ASSERT_EQUAL(owner_of(S), L, "the holder owns it")
	TEST_ASSERT_EQUAL(burn_of(L), S, "a second call returns the same datum")
	TEST_ASSERT_EQUAL(GLOB.lazy_states_made, made + 1, "one datum was made in all")

/// The state dies with its holder: nothing collects it.
/datum/unit_test/dq_lazy_state_dies_with_holder

/datum/unit_test/dq_lazy_state_dies_with_holder/Run()
	set_global("lazy_states_made", GLOB.lazy_states_made)
	var/obj/dq_lazy_lamp/L = new(test_floor())
	var/datum/dq_lazy_burn/S = burn_of(L)
	qdel(L)
	TEST_ASSERT(QDELETED(S), "the owned state is deleted with its holder")

/// A write to the state's var is observable: a draw reading `burn?.fuel` redraws; an unchanged write does not.
/datum/unit_test/dq_lazy_state_write_redraws

/datum/unit_test/dq_lazy_state_write_redraws/Run()
	set_global("lazy_states_made", GLOB.lazy_states_made)
	set_global("lazy_state_published", GLOB.lazy_state_published)
	var/obj/dq_lazy_lamp/L = allocate(/obj/dq_lazy_lamp, test_floor())
	refresh_flush()
	TEST_ASSERT_EQUAL(L.icon_state, "lamp0", "the lamp starts dark")
	burn_of(L) // makes the state; the make itself is not the write under test
	refresh_flush()
	var/published = GLOB.lazy_state_published
	burn_of(L).set_fuel(5)
	TEST_ASSERT_EQUAL(GLOB.lazy_state_published, published + 1, "the write was published on the holder")
	TEST_ASSERT(L.refresh_queued & DEP_DRAW, "a write the draw reads queues the redraw (queued: [L.refresh_queued])")
	refresh_flush()
	TEST_ASSERT_EQUAL(L.icon_state, "lamp1", "the draw followed the write")
	burn_of(L).set_fuel(5)
	TEST_ASSERT(!(L.refresh_queued & DEP_DRAW), "writing the same value queues nothing")
	burn_of(L).set_fuel(0)
	refresh_flush()
	TEST_ASSERT_EQUAL(L.icon_state, "lamp0", "writing it back redraws the dark lamp")

/// A write during the holder's teardown still returns something to write to, and keeps nothing.
/datum/unit_test/dq_lazy_state_during_teardown

/datum/unit_test/dq_lazy_state_during_teardown/Run()
	var/obj/dq_lazy_lamp/L = new(test_floor())
	qdel(L)
	var/datum/dq_lazy_burn/S = burn_of(L)
	TEST_ASSERT_NOTNULL(S, "an accessor on a deleted holder still answers")
	TEST_ASSERT_NULL(owner_of(S), "and what it answers belongs to nobody")
	TEST_ASSERT_NULL(L.burn, "the deleted holder keeps nothing")
