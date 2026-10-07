// The "Enter Passenger Compartment" search reads each compartment's own slot (OCCUPANT_SLOT_MECHA_PASSENGER), so an occupied compartment is
// skipped and the next free one is boarded.

/datum/unit_test/om/dq_mecha_passenger_slot

/datum/unit_test/om/dq_mecha_passenger_slot/run_om(list/made)
	var/turf/T = run_loc_floor_bottom_left
	var/obj/mecha/working/ripley/mech = allocate(/obj/mecha/working/ripley, T)
	var/obj/item/mecha_parts/mecha_equipment/tool/passenger/first = allocate(/obj/item/mecha_parts/mecha_equipment/tool/passenger, T)
	var/obj/item/mecha_parts/mecha_equipment/tool/passenger/second = allocate(/obj/item/mecha_parts/mecha_equipment/tool/passenger, T)
	first.attach(mech)
	second.attach(mech)
	first.door_locked = FALSE
	second.door_locked = FALSE
	var/mob/living/carbon/human/rider = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/boarder = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT(move_into(first, OCCUPANT_SLOT_MECHA_PASSENGER, rider), "a passenger takes the first compartment")
	mech.move_inside_passenger(boarder)
	scheduler_advance(5)
	TEST_ASSERT_EQUAL(first.slot_item(OCCUPANT_SLOT_MECHA_PASSENGER), rider, "the occupied compartment keeps its passenger")
	TEST_ASSERT_EQUAL(second.slot_item(OCCUPANT_SLOT_MECHA_PASSENGER), boarder, "the boarder goes to the free compartment, not the occupied one")

// The ledger's slot occupancy count follows move_into() and the release, and a mech's tracked passenger_count (what the remove_passenger
// requirement reads) follows its compartments.
/datum/unit_test/dq_slot_occupancy_count/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/mecha/working/ripley/mech = allocate(/obj/mecha/working/ripley, T)
	var/obj/item/mecha_parts/mecha_equipment/tool/passenger/seat = allocate(/obj/item/mecha_parts/mecha_equipment/tool/passenger, T)
	seat.attach(mech)
	var/mob/living/carbon/human/rider = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT_EQUAL(seat.slot_occupancy(OCCUPANT_SLOT_MECHA_PASSENGER), 0, "an empty compartment counts 0")
	TEST_ASSERT_EQUAL(mech.passenger_count, 0, "and the mech tracks no passengers")
	TEST_ASSERT(!mech.has_passengers(null), "so the no-passengers requirement refuses")
	TEST_ASSERT(move_into(seat, OCCUPANT_SLOT_MECHA_PASSENGER, rider), "a passenger takes the compartment")
	TEST_ASSERT_EQUAL(seat.slot_occupancy(OCCUPANT_SLOT_MECHA_PASSENGER), 1, "move_into writes the count")
	TEST_ASSERT_EQUAL(mech.passenger_count, 1, "the mech's tracked count follows")
	TEST_ASSERT(mech.has_passengers(null), "and the requirement allows")
	rider.forceMove(T)
	TEST_ASSERT_EQUAL(seat.slot_occupancy(OCCUPANT_SLOT_MECHA_PASSENGER), 0, "the release writes it back")
	TEST_ASSERT_EQUAL(mech.passenger_count, 0, "and the mech's count follows the release")
