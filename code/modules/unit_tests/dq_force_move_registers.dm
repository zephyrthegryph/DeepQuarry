// A forceMove into a holder that declares a slot registers in its default slot through the ledger's own note_enter(), like move_into() does,
// also when the holder never built its ledger; leaving unregisters; a thing that came through move_into() is not registered twice.

/// A real fishing net with the one slot a net's draw reads (the net itself declares none yet).
/obj/item/material/fishing_net/dq_slotted_test
	abstract_type = /obj/item/material/fishing_net/dq_slotted_test // a fixture: the look sweeps skip it

CAPABILITIES(/obj/item/material/fishing_net/dq_slotted_test)
	slot(CONTAINER_SLOT_FUEL)

/// A real glass jar with a slot, for the same.
/obj/item/glass_jar/dq_slotted_test
	abstract_type = /obj/item/glass_jar/dq_slotted_test // a fixture: the look sweeps skip it

CAPABILITIES(/obj/item/glass_jar/dq_slotted_test)
	slot(CONTAINER_SLOT_FUEL)

/datum/unit_test/dq_force_move_registers_in_net

/datum/unit_test/dq_force_move_registers_in_net/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/item/material/fishing_net/dq_slotted_test/holder = allocate(/obj/item/material/fishing_net/dq_slotted_test, T)
	var/mob/living/simple_mob/animal/passive/mouse/critter = allocate(/mob/living/simple_mob/animal/passive/mouse, T)
	dq_force_move_check(holder, critter, CONTAINER_SLOT_FUEL)

/datum/unit_test/dq_force_move_registers_in_jar

/datum/unit_test/dq_force_move_registers_in_jar/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/item/glass_jar/dq_slotted_test/holder = allocate(/obj/item/glass_jar/dq_slotted_test, T)
	var/mob/living/simple_mob/animal/passive/mouse/critter = allocate(/mob/living/simple_mob/animal/passive/mouse, T)
	dq_force_move_check(holder, critter, CONTAINER_SLOT_FUEL)

/// Moves `critter` into `holder` with forceMove() (the holder's ledger was never asked for), out again, in through move_into(), and checks the ledger each time.
/datum/unit_test/proc/dq_force_move_check(atom/holder, atom/movable/critter, slot_id)
	TEST_ASSERT_NULL(holder.containment_ledger(), "the holder starts without a ledger (nothing asked what it holds)")
	TEST_ASSERT(critter.forceMove(holder), "forceMove puts the creature in")
	var/datum/ledger/L = holder.containment_ledger()
	TEST_ASSERT(L, "the arrival made the holder's ledger")
	TEST_ASSERT(critter in holder.slot_contents(slot_id), "the creature is registered in the declared slot")
	TEST_ASSERT(critter in holder.slot_contents(), "and in the holder's slot list")
	TEST_ASSERT_EQUAL(holder.slot_occupancy(slot_id), 1, "the slot's occupancy is 1")
	TEST_ASSERT_EQUAL(L.tracked, 1, "registered once")
	var/serial = L.entries[critter][LEDGER_E_SERIAL]
	critter.forceMove(holder.loc || get_turf(holder))
	TEST_ASSERT(!(critter in holder.slot_contents(slot_id)), "leaving unregisters the creature")
	TEST_ASSERT_EQUAL(holder.slot_occupancy(slot_id), 0, "the occupancy is back to 0")
	TEST_ASSERT_EQUAL(L.tracked, 0, "the ledger tracks nothing")
	TEST_ASSERT(move_into(holder, slot_id, critter), "move_into puts it back")
	TEST_ASSERT_EQUAL(holder.slot_occupancy(slot_id), 1, "one entry after the move_into route")
	TEST_ASSERT_EQUAL(L.tracked, 1, "the move_into route did not register it twice")
	TEST_ASSERT_EQUAL(length(holder.slot_contents(slot_id)), 1, "one thing in the slot")
	TEST_ASSERT(L.entries[critter][LEDGER_E_SERIAL] != serial, "it is a new entry after leaving and returning")
	critter.forceMove(get_turf(holder))
