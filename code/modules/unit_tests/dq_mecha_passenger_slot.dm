// The "Enter Passenger Compartment" search reads each compartment's own slot (OCCUPANT_SLOT_MECHA_PASSENGER), so an occupied compartment is
// skipped and the next free one is boarded.

/datum/unit_test/dq_mecha_passenger_slot/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/mecha/working/ripley/mech = allocate(/obj/mecha/working/ripley, T)
	var/obj/item/mecha_parts/mecha_equipment/tool/passenger/first = allocate(/obj/item/mecha_parts/mecha_equipment/tool/passenger, T)
	var/obj/item/mecha_parts/mecha_equipment/tool/passenger/second = allocate(/obj/item/mecha_parts/mecha_equipment/tool/passenger, T)
	first.attach(mech)
	second.attach(mech)
	var/mob/living/carbon/human/rider = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/boarder = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT(move_into(first, OCCUPANT_SLOT_MECHA_PASSENGER, rider), "a passenger takes the first compartment")
	mech.move_inside_passenger(boarder)
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(first.slot_item(OCCUPANT_SLOT_MECHA_PASSENGER), rider, "the occupied compartment keeps its passenger")
	TEST_ASSERT_EQUAL(second.slot_item(OCCUPANT_SLOT_MECHA_PASSENGER), boarder, "the boarder goes to the free compartment, not the occupied one")
