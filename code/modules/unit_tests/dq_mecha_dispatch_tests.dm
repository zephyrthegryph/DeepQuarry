// Mecha equipment dispatch (the old proc_res table): an active jetpack takes over
// movement and an attached energy relay takes over charge reads, through typed
// refs on the chassis that attach/detach and toggling keep in step.

/datum/unit_test/dq_mecha_jetpack_dispatch

/datum/unit_test/dq_mecha_jetpack_dispatch/Run()
	var/turf/T = test_floor()
	var/obj/mecha/working/ripley/mech = allocate(/obj/mecha/working/ripley, T)
	var/obj/item/mecha_parts/mecha_equipment/tool/jetpack/jet = allocate(/obj/item/mecha_parts/mecha_equipment/tool/jetpack, T)
	TEST_ASSERT(jet.can_attach(mech), "a jetpack should attach to a bare ripley")
	jet.attach(mech)
	TEST_ASSERT_NULL(mech.active_jetpack, "an attached but idle jetpack should not take over movement")
	jet.turn_on()
	TEST_ASSERT_EQUAL(mech.active_jetpack, jet, "an active jetpack should take over movement")
	var/obj/item/mecha_parts/mecha_equipment/tool/jetpack/second = allocate(/obj/item/mecha_parts/mecha_equipment/tool/jetpack, T)
	TEST_ASSERT(!second.can_attach(mech), "a second jetpack should not attach while one is active")
	jet.turn_off()
	TEST_ASSERT_NULL(mech.active_jetpack, "turning the jetpack off should hand movement back to the chassis")
	jet.turn_on()
	jet.detach()
	TEST_ASSERT_NULL(mech.active_jetpack, "detaching an active jetpack should clear the chassis ref")

/datum/unit_test/dq_mecha_energy_relay_dispatch

/datum/unit_test/dq_mecha_energy_relay_dispatch/Run()
	var/turf/T = test_floor()
	var/obj/mecha/working/ripley/mech = allocate(/obj/mecha/working/ripley, T)
	var/obj/item/mecha_parts/mecha_equipment/tesla_energy_relay/relay = allocate(/obj/item/mecha_parts/mecha_equipment/tesla_energy_relay, T)
	TEST_ASSERT(relay.can_attach(mech), "an energy relay should attach to a bare ripley")
	relay.attach(mech)
	TEST_ASSERT_EQUAL(mech.energy_relay, relay, "an attached relay should take over charge reads")
	var/obj/item/mecha_parts/mecha_equipment/tesla_energy_relay/second = allocate(/obj/item/mecha_parts/mecha_equipment/tesla_energy_relay, T)
	TEST_ASSERT(!second.can_attach(mech), "a second relay should not attach")
	relay.equip_ready = TRUE
	TEST_ASSERT_EQUAL(mech.get_charge(), mech.dyngetcharge(), "an idle relay should report the chassis's own charge")
	relay.detach()
	TEST_ASSERT_NULL(mech.energy_relay, "detaching the relay should clear the chassis ref")
