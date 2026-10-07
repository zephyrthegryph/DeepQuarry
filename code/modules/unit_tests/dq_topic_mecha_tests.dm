// The exosuit's control-panel links (its hrefs), through the input inbox: the pilot's reach the controls, a stranger's do nothing. These read the same
// whether a link is a TOPIC_ACTION row or an op.

/datum/unit_test/dq_topic_mecha_panel

/datum/unit_test/dq_topic_mecha_panel/Run()
	var/turf/T = test_floor()
	var/obj/mecha/working/ripley/mech = allocate(/obj/mecha/working/ripley, T)
	var/mob/living/carbon/human/pilot = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/stranger = allocate(/mob/living/carbon/human)
	TEST_ASSERT(move_into(mech, MECHA_SLOT_PILOT, pilot), "the pilot gets in")
	// the pilot's controls
	var/lights_before = mech.lights
	inbox_topic(pilot, mech, list("toggle_lights" = 1))
	TEST_ASSERT(mech.lights != lights_before, "the pilot's lights link toggles the lights")
	var/mic_before = mech.radio.broadcasting
	inbox_topic(pilot, mech, list("rmictoggle" = 1))
	TEST_ASSERT(mech.radio.broadcasting != mic_before, "the pilot's microphone link toggles the radio")
	var/spk_before = mech.radio.listening
	inbox_topic(pilot, mech, list("rspktoggle" = 1))
	TEST_ASSERT(mech.radio.listening != spk_before, "the pilot's speaker link toggles the radio")
	var/lock_before = mech.add_req_access
	inbox_topic(pilot, mech, list("toggle_id_upload" = 1))
	TEST_ASSERT(mech.add_req_access != lock_before, "the pilot's ID upload link toggles the panel")
	inbox_topic(pilot, mech, list("dna_lock" = 1))
	TEST_ASSERT_EQUAL(mech.dna, pilot.dna?.unique_enzymes, "the pilot's DNA lock link keys the suit to their DNA")
	inbox_topic(pilot, mech, list("reset_dna" = 1))
	TEST_ASSERT_NULL(mech.dna, "the reset link clears it")
	// a number from the link crosses as a number; the frequency moves by it
	var/freq_before = mech.radio.frequency
	inbox_topic(pilot, mech, list("rfreq" = "2"))
	TEST_ASSERT_EQUAL(mech.radio.frequency, sanitize_frequency(freq_before + 2), "the frequency link moves the radio by its delta")
	// someone who is not the pilot and cannot reach it does nothing
	lights_before = mech.lights
	inbox_topic(stranger, mech, list("toggle_lights" = 1))
	TEST_ASSERT_EQUAL(mech.lights, lights_before, "a stranger's lights link does nothing")
	mic_before = mech.radio.broadcasting
	inbox_topic(stranger, mech, list("rmictoggle" = 1))
	TEST_ASSERT_EQUAL(mech.radio.broadcasting, mic_before, "a stranger's microphone link does nothing")
	inbox_topic(stranger, mech, list("dna_lock" = 1))
	TEST_ASSERT_NULL(mech.dna, "a stranger cannot lock the suit to their DNA")

/datum/unit_test/dq_topic_mecha_equipment

/datum/unit_test/dq_topic_mecha_equipment/Run()
	var/turf/T = test_floor()
	var/obj/mecha/working/ripley/mech = allocate(/obj/mecha/working/ripley, T)
	var/mob/living/carbon/human/pilot = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/stranger = allocate(/mob/living/carbon/human)
	TEST_ASSERT(move_into(mech, MECHA_SLOT_PILOT, pilot), "the pilot gets in")
	var/obj/item/mecha_parts/mecha_equipment/tool/jetpack/jet = allocate(/obj/item/mecha_parts/mecha_equipment/tool/jetpack, T)
	var/obj/item/mecha_parts/mecha_equipment/tool/jetpack/loose = allocate(/obj/item/mecha_parts/mecha_equipment/tool/jetpack, T)
	jet.attach(mech)
	// selecting names equipment by ref, and only equipment mounted on this suit is found
	inbox_topic(pilot, mech, list("select_equip" = "[REF(jet)]"))
	TEST_ASSERT_EQUAL(mech.selected, jet, "the pilot selects mounted equipment by its ref")
	var/obj/item/mecha_parts/mecha_equipment/before = mech.selected
	inbox_topic(pilot, mech, list("select_equip" = "[REF(loose)]"))
	TEST_ASSERT_EQUAL(mech.selected, before, "equipment that is not mounted on this suit cannot be selected")
	// the equipment's own links: the pilot's reach it, a stranger's do not
	inbox_topic(stranger, jet, list("toggle" = 1))
	TEST_ASSERT_NULL(mech.active_jetpack, "a stranger cannot switch the jetpack on")
	inbox_topic(pilot, jet, list("toggle" = 1))
	TEST_ASSERT_EQUAL(mech.active_jetpack, jet, "the pilot's jetpack link switches it on")
	inbox_topic(pilot, jet, list("toggle" = 1))
	TEST_ASSERT_NULL(mech.active_jetpack, "and off again")
	inbox_topic(stranger, jet, list("detach" = 1))
	TEST_ASSERT_EQUAL(jet.chassis, mech, "a stranger cannot detach equipment")
	inbox_topic(pilot, jet, list("detach" = 1))
	TEST_ASSERT_NULL(jet.chassis, "the pilot's detach link takes it off the suit")
