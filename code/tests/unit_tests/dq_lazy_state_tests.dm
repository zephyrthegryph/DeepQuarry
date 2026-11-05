// Lazy owned state (owns_one(lazy = TRUE), code/engine/declare/lazy_state.dm): rarely used state is a small datum the holder owns, made on its first write.

/// The state datum: one tracked number a draw reads.
/datum/dq_burn_state
	var/fuel = 0
	var/limit = 7

/// A drawn fixture holding the state lazily.
/obj/dq_lazy_lamp
	icon = 'icons/obj/lighting.dmi'
	icon_state = "lamp0"
	var/datum/dq_burn_state/dq_burn

CAPABILITIES(/obj/dq_lazy_lamp)
	owns_one(nameof(dq_burn), /datum/dq_burn_state, lazy = TRUE)

/obj/dq_lazy_lamp/draw(datum/look/look)
	..()
	look.state(STATE_GET(src, dq_burn, fuel) > 0 ? "lamp1" : "lamp0")

/// A read allocates nothing; the first write makes the datum once, owned by the holder; later writes reuse it.
/datum/unit_test/dq_lazy_state_made_on_first_write

/datum/unit_test/dq_lazy_state_made_on_first_write/Run()
	var/obj/dq_lazy_lamp/L = allocate(/obj/dq_lazy_lamp, test_floor())
	var/made = GLOB.lazy_states_made
	set_global("lazy_states_made", made) // the counter moves in this test; teardown restores it
	TEST_ASSERT_NULL(L.dq_burn, "a fresh holder has no state datum")
	TEST_ASSERT_EQUAL(L.dq_burn?.fuel, null, "a read of an unmade state is null")
	TEST_ASSERT_EQUAL(GLOB.lazy_states_made, made, "a read made nothing")
	var/datum/dq_burn_state/S = dq_burn_of(L)
	TEST_ASSERT_NOTNULL(S, "dq_burn_of() makes the state")
	TEST_ASSERT_EQUAL(L.dq_burn, S, "the holder's var names it")
	TEST_ASSERT_EQUAL(owner_of(S), L, "the holder owns it")
	TEST_ASSERT_EQUAL(dq_burn_of(L), S, "a second call returns the same datum")
	TEST_ASSERT_EQUAL(GLOB.lazy_states_made, made + 1, "one datum was made in all")

/// The state dies with its holder: nothing collects it.
/datum/unit_test/dq_lazy_state_dies_with_holder

/datum/unit_test/dq_lazy_state_dies_with_holder/Run()
	set_global("lazy_states_made", GLOB.lazy_states_made)
	var/obj/dq_lazy_lamp/L = new(test_floor())
	var/datum/dq_burn_state/S = dq_burn_of(L)
	qdel(L)
	TEST_ASSERT(QDELETED(S), "the owned state is deleted with its holder")

/// A write to the state's var is observable: a draw reading `dq_burn?.fuel` redraws; an unchanged write does not.
/datum/unit_test/dq_lazy_state_write_redraws

/datum/unit_test/dq_lazy_state_write_redraws/Run()
	set_global("lazy_states_made", GLOB.lazy_states_made)
	set_global("lazy_state_published", GLOB.lazy_state_published)
	var/obj/dq_lazy_lamp/L = allocate(/obj/dq_lazy_lamp, test_floor())
	refresh_flush()
	TEST_ASSERT_EQUAL(L.icon_state, "lamp0", "the lamp starts dark")
	dq_burn_of(L) // makes the state; the make itself is not the write under test
	refresh_flush()
	var/published = GLOB.lazy_state_published
	dq_burn_of(L).set_fuel(5)
	TEST_ASSERT_EQUAL(GLOB.lazy_state_published, published + 1, "the write was published on the holder")
	TEST_ASSERT(L.refresh_queued & DEP_DRAW, "a write the draw reads queues the redraw (queued: [L.refresh_queued])")
	refresh_flush()
	TEST_ASSERT_EQUAL(L.icon_state, "lamp1", "the draw followed the write")
	dq_burn_of(L).set_fuel(5)
	TEST_ASSERT(!(L.refresh_queued & DEP_DRAW), "writing the same value queues nothing")
	dq_burn_of(L).set_fuel(0)
	refresh_flush()
	TEST_ASSERT_EQUAL(L.icon_state, "lamp0", "writing it back redraws the dark lamp")

/// A write during the holder's teardown still returns something to write to, and keeps nothing.
/datum/unit_test/dq_lazy_state_during_teardown

/datum/unit_test/dq_lazy_state_during_teardown/Run()
	var/obj/dq_lazy_lamp/L = new(test_floor())
	qdel(L)
	var/datum/dq_burn_state/S = dq_burn_of(L)
	TEST_ASSERT_NOTNULL(S, "an accessor on a deleted holder still answers")
	TEST_ASSERT_NULL(owner_of(S), "and what it answers belongs to nobody")
	TEST_ASSERT_NULL(L.dq_burn, "the deleted holder keeps nothing")

/// STATE_GET reads the field, or the state type's own default while the holder has no state, and allocates nothing.
/datum/unit_test/dq_lazy_state_get_reads_default

/datum/unit_test/dq_lazy_state_get_reads_default/Run()
	set_global("lazy_states_made", GLOB.lazy_states_made)
	var/obj/dq_lazy_lamp/L = allocate(/obj/dq_lazy_lamp, test_floor())
	var/made = GLOB.lazy_states_made
	TEST_ASSERT_EQUAL(STATE_GET(L, dq_burn, limit), 7, "no state: the type's default")
	TEST_ASSERT_EQUAL(STATE_GET(L, dq_burn, fuel), 0, "no state: a zero default")
	TEST_ASSERT_EQUAL(GLOB.lazy_states_made, made, "reads made nothing")
	dq_burn_of(L).set_limit(3)
	TEST_ASSERT_EQUAL(STATE_GET(L, dq_burn, limit), 3, "state: the field")
	TEST_ASSERT_EQUAL(STATE_GET(L, dq_burn, fuel), 0, "state: an untouched field keeps its default")
	dq_burn_of(L).set_limit(7)
	TEST_ASSERT_NOTNULL(L.dq_burn, "a write back to the default frees nothing")

/// x_clear() ends the feature: the datum goes and the var reads null (defaults again); a later write makes a new one.
/datum/unit_test/dq_lazy_state_clear

/datum/unit_test/dq_lazy_state_clear/Run()
	set_global("lazy_states_made", GLOB.lazy_states_made)
	set_global("lazy_states_cleared", GLOB.lazy_states_cleared)
	var/obj/dq_lazy_lamp/L = allocate(/obj/dq_lazy_lamp, test_floor())
	var/datum/dq_burn_state/S = dq_burn_of(L)
	S.set_limit(1)
	dq_burn_clear(L)
	TEST_ASSERT_NULL(L.dq_burn, "the var is null again")
	TEST_ASSERT(QDELETED(S), "the cleared state is deleted")
	TEST_ASSERT_EQUAL(STATE_GET(L, dq_burn, limit), 7, "defaults again")
	dq_burn_clear(L) // clearing nothing is fine
	TEST_ASSERT(dq_burn_of(L) != S, "a later write makes a new datum")

/// The var form: STATE_SET makes nothing for a default value, makes the state for another, and drops it when every field is default again.
/datum/unit_test/dq_lazy_state_set_default_rules

/datum/unit_test/dq_lazy_state_set_default_rules/Run()
	set_global("lazy_states_made", GLOB.lazy_states_made)
	set_global("lazy_states_cleared", GLOB.lazy_states_cleared)
	var/obj/dq_lazy_lamp/L = allocate(/obj/dq_lazy_lamp, test_floor())
	STATE_SET(L, dq_burn, limit, 7)
	TEST_ASSERT_NULL(L.dq_burn, "a default write with no state makes none")
	STATE_SET(L, dq_burn, limit, 3)
	TEST_ASSERT_NOTNULL(L.dq_burn, "a non-default write makes the state")
	STATE_SET(L, dq_burn, fuel, 2)
	STATE_SET(L, dq_burn, limit, 7)
	TEST_ASSERT_NOTNULL(L.dq_burn, "a field still off its default keeps the state")
	STATE_SET(L, dq_burn, fuel, 0)
	TEST_ASSERT_NULL(L.dq_burn, "the state goes when every field is default again")

/// A table-form holder carries no var: its states are rows keyed by its slot, found by peek, dropped when it is destroyed.
/obj/dq_lazy_table_probe

CAPABILITIES(/obj/dq_lazy_table_probe)
	lazy_state(dq_tab, /datum/dq_tab_state)

/datum/dq_tab_state
	parent_type = /datum/lazy_state
	var/amount = 4
	var/tag_text

/datum/unit_test/dq_lazy_state_table_form

/datum/unit_test/dq_lazy_state_table_form/Run()
	set_global("lazy_states_made", GLOB.lazy_states_made)
	set_global("lazy_states_cleared", GLOB.lazy_states_cleared)
	var/obj/dq_lazy_table_probe/P = new(test_floor())
	TEST_ASSERT_EQUAL(P.handle_slot, 0, "a fresh holder has no slot")
	TEST_ASSERT_EQUAL(STATE_PEEK(P, dq_tab, amount), 4, "no row: the type's default")
	TEST_ASSERT_EQUAL(P.handle_slot, 0, "a read gives the holder no slot")
	STATE_SET(P, dq_tab, amount, 4)
	TEST_ASSERT_NULL(dq_tab_peek(P), "a default write with no row makes none")
	STATE_SET(P, dq_tab, amount, 9)
	var/datum/dq_tab_state/S = dq_tab_peek(P)
	TEST_ASSERT_NOTNULL(S, "a non-default write makes the row")
	TEST_ASSERT_EQUAL(STATE_PEEK(P, dq_tab, amount), 9, "and reads back")
	TEST_ASSERT_EQUAL(S.lazy_holder_slot, P.handle_slot, "the row names its holder's slot")
	STATE_SET(P, dq_tab, amount, 4)
	TEST_ASSERT_NULL(dq_tab_peek(P), "the row goes when every field is default again")
	var/datum/dq_tab_state/T = dq_tab_of(P)
	T.set_tag_text("x")
	qdel(P)
	TEST_ASSERT_NULL(GLOB.lazy_state_tables["dq_tab"]?[T.lazy_holder_slot], "a destroyed holder leaves no row in the table")
