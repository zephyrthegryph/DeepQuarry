/// Exercise the actual declared entry under an unrelated native ambient actor.
/obj/interim_micro_passenger_actor_click
	var/obj/mecha/micro/mech
	var/mob/actor
	var/datum/interaction/entry

/obj/interim_micro_passenger_actor_click/Click(location, control, params)
	entry.perform(actor, mech, null)

/datum/unit_test/interim_micro_passenger_actor/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/turf/far = get_step(get_step(get_step(T, EAST), EAST), EAST)
	TEST_ASSERT(isfloorturf(far), "a real distant floor exists for the parent boarding guard")
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/bystander = allocate(/mob/living/carbon/human, T)
	actor.enable_godmode()
	bystander.enable_godmode()
	actor.resize(0.25, animate = FALSE, ignore_prefs = TRUE)
	TEST_ASSERT(actor.get_effective_size(TRUE) < 0.5, "actual resize produces a human admitted by the existing micro size gate")
	TEST_ASSERT(bystander.get_effective_size(TRUE) >= 0.5, "actual unrelated human fails the unchanged micro size gate")
	var/obj/mecha/micro/utility/gopher/mech = allocate(/obj/mecha/micro/utility/gopher, T)
	var/obj/item/mecha_parts/mecha_equipment/tool/passenger/bay = allocate(/obj/item/mecha_parts/mecha_equipment/tool/passenger, T)
	TEST_ASSERT(bay.can_attach(mech), "actual passenger component fits the real hull equipment capacity")
	bay.attach(mech)
	TEST_ASSERT_EQUAL(bay.chassis, mech, "actual attachment associates the exact chassis")
	TEST_ASSERT_EQUAL(bay.loc, mech, "actual equipment containment physically mounts the passenger compartment")
	TEST_ASSERT(mech.pred_mecha_has_passenger_bay(actor, mech, null), "actual mounted ledger exposes the declared passenger entry")
	TEST_ASSERT_NULL(bay.slot_item(OCCUPANT_SLOT_MECHA_PASSENGER), "actual passenger compartment starts empty")
	var/datum/interaction/entry
	for(var/datum/interaction/candidate as anything in interaction_candidates(mech))
		if(candidate.effect == nameof(/obj/mecha/proc/move_inside_passenger))
			entry = candidate
			break
	TEST_ASSERT_NOTNULL(entry, "actual micro mech inherits its declared Enter Passenger Compartment interaction")
	TEST_ASSERT_NULL(entry.why_not(actor, mech, null), "actual resized human satisfies the inherited declared entry requirements")
	mech.move_inside_passenger(null, null, null)
	TEST_ASSERT_NULL(bay.slot_item(OCCUPANT_SLOT_MECHA_PASSENGER), "absent explicit actor cannot establish a passenger slot")
	entry.perform(bystander, mech, null)
	test_time(5 SECONDS)
	TEST_ASSERT_NULL(bay.slot_item(OCCUPANT_SLOT_MECHA_PASSENGER), "the actual large human cannot enter the micro passenger bay")
	TEST_ASSERT_EQUAL(bystander.loc, T, "size refusal preserves the actual unrelated human floor")
	TEST_ASSERT(bay.door_locked, "actual initialized compartment starts locked")
	entry.perform(actor, mech, null)
	test_time(5 SECONDS)
	TEST_ASSERT_NULL(bay.slot_item(OCCUPANT_SLOT_MECHA_PASSENGER), "real locked compartment refuses actual small-human boarding")
	TEST_ASSERT_EQUAL(actor.loc, T, "real lock refusal preserves the actual resized human floor")
	perform_op(actor, bay, "toggle_lock", null, ORIGIN_SYSTEM) // the hatch control link, as the system (the pilot gate is the link's, not the hatch's)
	TEST_ASSERT(!bay.door_locked, "actual existing hatch control unlocks the real mounted compartment")
	actor.forceMove(far)
	TEST_ASSERT(!actor.Adjacent(mech), "the actual distant resized human fails the parent proximity guard")
	entry.perform(actor, mech, null)
	test_time(5 SECONDS)
	TEST_ASSERT_NULL(bay.slot_item(OCCUPANT_SLOT_MECHA_PASSENGER), "actual distant human cannot establish a passenger slot")
	TEST_ASSERT_EQUAL(actor.loc, far, "actual parent range refusal preserves the distant actor")
	actor.forceMove(T)
	var/obj/interim_micro_passenger_actor_click/native = allocate(/obj/interim_micro_passenger_actor_click, T)
	native.mech = mech
	native.actor = actor
	native.entry = entry
	km_synthetic_click(bystander, native)
	test_time(3 SECONDS)
	TEST_ASSERT_NULL(bay.slot_item(OCCUPANT_SLOT_MECHA_PASSENGER), "actual accepted boarding waits its genuine four-second duration")
	TEST_ASSERT_EQUAL(actor.loc, T, "actual boarding has not moved the supplied small human before its deadline")
	test_time(2 SECONDS)
	TEST_ASSERT_EQUAL(bay.slot_item(OCCUPANT_SLOT_MECHA_PASSENGER), actor, "actual declared entry and timed parent completion board the supplied small human")
	TEST_ASSERT_EQUAL(actor.loc, bay, "real timed completion physically moves the supplied actor into the mounted bay")
	TEST_ASSERT_EQUAL(bystander.loc, T, "unrelated large ambient native actor never enters the compartment")
	TEST_ASSERT_NULL(mech.slot_item(MECHA_SLOT_PILOT), "real passenger boarding does not fabricate a mech pilot")
	TEST_ASSERT_EQUAL(bay.chassis, mech, "actual boarding preserves the original equipment chassis association")
	bay.go_out()
	TEST_ASSERT_NULL(bay.slot_item(OCCUPANT_SLOT_MECHA_PASSENGER), "real disembarkation clears the exact actual passenger ledger slot")
	TEST_ASSERT_EQUAL(actor.loc, T, "real disembarkation returns the same human to the original floor")
