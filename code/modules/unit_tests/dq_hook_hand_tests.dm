// Hand-converted om_hook sites: each test drives the real trigger of a hook that became observe() and checks what the handler did.
// The handlers take (datum/act/notice/N); the notices of the before/ events that only watch are twins of the event (om_event_map.json).

/// A receiver that counts HasProximity calls.
/obj/dq_hook_hand_receiver
	var/prox_calls = 0

/obj/dq_hook_hand_receiver/HasProximity(atom/movable/AM)
	prox_calls++

/datum/unit_test/dq_hook_hand_sticky_paper_reset
	var/obj/item/paper/sticky/note

/datum/unit_test/dq_hook_hand_sticky_paper_reset/Run()
	var/turf/start = run_loc_floor_bottom_left
	var/turf/next = get_step(start, EAST)
	TEST_ASSERT_NOTNULL(next, "no tile east of the test origin")
	note = allocate(/obj/item/paper/sticky, start)
	note.pixel_x = 9
	note.pixel_y = -7
	note.forceMove(next)
	TEST_ASSERT_EQUAL(note.pixel_x, 0, "moving a sticky note reset its x offset through the movable_attempted_move observer")
	TEST_ASSERT_EQUAL(note.pixel_y, 0, "and its y offset")

/datum/unit_test/dq_hook_hand_wet_stacks_traits

/datum/unit_test/dq_hook_hand_wet_stacks_traits/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	H.adjust_wet_stacks(5)
	var/datum/status_effect/fire_handler/wet_stacks/wet = H.has_status_effect(/datum/status_effect/fire_handler/wet_stacks)
	TEST_ASSERT_NOTNULL(wet, "wet stacks applied")
	TEST_ASSERT_EQUAL(wet.stack_modifier, -1, "the default stack modifier")
	add_trait(H, TRAIT_WET_FOR_LONGER, "dq_hook_hand")
	TEST_ASSERT_EQUAL(wet.stack_modifier, -3.5, "trait_gained(TRAIT_WET_FOR_LONGER) retunes the stack modifier")
	remove_trait(H, TRAIT_WET_FOR_LONGER, "dq_hook_hand")
	TEST_ASSERT_EQUAL(wet.stack_modifier, -1, "trait_lost(TRAIT_WET_FOR_LONGER) retunes it back")
	add_trait(H, TRAIT_SLIPPERY_WHEN_WET, "dq_hook_hand")
	TEST_ASSERT(has_trait(H, TRAIT_NO_SLIP_WATER), "trait_gained(TRAIT_SLIPPERY_WHEN_WET) makes the wet mob slippery")
	remove_trait(H, TRAIT_SLIPPERY_WHEN_WET, "dq_hook_hand")
	TEST_ASSERT(!has_trait(H, TRAIT_NO_SLIP_WATER), "trait_lost(TRAIT_SLIPPERY_WHEN_WET) ends it")

/datum/unit_test/dq_hook_hand_geiger_watches_pulses

/datum/unit_test/dq_hook_hand_geiger_watches_pulses/Run()
	var/obj/item/geiger/counter = allocate(/obj/item/geiger, run_loc_floor_bottom_left)
	var/datum/radiation_pulse_information/pulse = new
	pulse.strength = 40
	pulse.threshold = 0.2
	pulse.max_range = 3
	pulse.chance = 100
	PUBLISH_LEGACY(counter, /datum/notice/in_range_of_irradiation, pulse, 0.5)
	TEST_ASSERT_EQUAL(counter.last_radiation_strength, 40, "the in_range_of_irradiation notice twin reached the geiger's handler")
	TEST_ASSERT_EQUAL(counter.insulation_deficit, 0.3, "with the insulation it was told")
	qdel(pulse)

/datum/unit_test/dq_hook_hand_container_connector_follows_host

/datum/unit_test/dq_hook_hand_container_connector_follows_host/Run()
	var/turf/start = run_loc_floor_bottom_left
	var/turf/next = get_step(start, EAST)
	var/obj/structure/closet/crate/crate = allocate(/obj/structure/closet/crate, start)
	var/obj/dq_hook_hand_receiver/host = allocate(/obj/dq_hook_hand_receiver, start)
	var/datum/proximity_monitor/monitor = new(host, 1)
	var/before = host.prox_calls
	host.forceMove(crate)
	TEST_ASSERT(host.prox_calls > before, "the host moving into a container reached the monitor's moved handler (the host is its own receiver)")
	before = host.prox_calls
	host.forceMove(next)
	TEST_ASSERT(host.prox_calls > before, "and moving out again did")
	qdel(monitor)

/datum/unit_test/dq_hook_hand_silo_examine

/datum/unit_test/dq_hook_hand_silo_examine/Run()
	var/obj/machinery/ore_silo/silo = allocate(/obj/machinery/ore_silo, run_loc_floor_bottom_left)
	var/datum/material_container/container = silo.materials
	TEST_ASSERT_NOTNULL(container, "the silo has a material container")
	var/datum/material/steel = get_material_by_name(MAT_STEEL)
	container.materials[steel] = 2000
	var/list/texts = list()
	PUBLISH_LEGACY(silo, /datum/notice/examine, null, texts)
	TEST_ASSERT(length(texts) > 0, "the examine notice reached the container's observer, which listed what it holds")
