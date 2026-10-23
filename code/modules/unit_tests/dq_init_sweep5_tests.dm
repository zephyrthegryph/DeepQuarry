// The Initialize() overrides init sweep 5 took out: what each one set up before or after `..()` is now a derives() computed at init, a
// setup(PROC_REF(x)) hook that runs once the instance's Initialize() chain has returned (ancestors first), or a with_params hook that runs first.

/obj/machinery/shield_gen/dq_anchored_probe
	anchored = TRUE

/obj/machinery/navbeacon/patrol/dq_stop_probe
	next_patrol = "dq_next_stop"

/obj/machinery/reagent_refinery/mixer/dq_west_probe
	dir = WEST

// The public-band presets add their band to the frequencies they are given.
/datum/unit_test/dq_init_sweep5_telecomms_bands

/datum/unit_test/dq_init_sweep5_telecomms_bands/Run()
	var/turf/T = dq_containment_floor()
	var/obj/machinery/telecomms/receiver/preset_right/right = allocate(/obj/machinery/telecomms/receiver/preset_right, T)
	TEST_ASSERT(AI_FREQ in right.freq_listening, "the right receiver keeps the frequencies it was given")
	TEST_ASSERT(PUBLIC_LOW_FREQ in right.freq_listening, "and takes the bottom of the public band")
	TEST_ASSERT(PUB_FREQ in right.freq_listening, "and the public channel")
	TEST_ASSERT_EQUAL(length(right.freq_listening), length(right.freq_listening | list()), "and none of them twice")

	var/turf/east = get_step(T, EAST)
	var/obj/machinery/telecomms/bus/preset_two/bus = allocate(/obj/machinery/telecomms/bus/preset_two, east)
	TEST_ASSERT(SUP_FREQ in bus.freq_listening, "the second bus keeps the frequencies it was given")
	TEST_ASSERT(PUBLIC_LOW_FREQ in bus.freq_listening, "and takes the public band")
	TEST_ASSERT(!(PUB_FREQ in bus.freq_listening), "but not the public channel")

	var/obj/machinery/telecomms/server/presets/unused/server = allocate(/obj/machinery/telecomms/server/presets/unused, get_step(east, EAST))
	TEST_ASSERT(PUBLIC_LOW_FREQ in server.freq_listening, "the unused server takes the public band")
	TEST_ASSERT(!(PUB_FREQ in server.freq_listening), "but not the public channel")
	TEST_ASSERT(!(AI_FREQ in server.freq_listening), "nor the AI's")

// The data-only starts: a patrol beacon's codes, the custom dispenser's gear, the mixer's arm.
/datum/unit_test/dq_init_sweep5_derived_starts

/datum/unit_test/dq_init_sweep5_derived_starts/Run()
	var/turf/T = dq_containment_floor()
	var/obj/machinery/navbeacon/patrol/dq_stop_probe/beacon = allocate(/obj/machinery/navbeacon/patrol/dq_stop_probe, T)
	TEST_ASSERT_EQUAL(beacon.codes["patrol"], 1, "a patrol beacon is a patrol stop")
	TEST_ASSERT_EQUAL(beacon.codes["next_patrol"], "dq_next_stop", "and names the next stop the map gave it")

	var/turf/east = get_step(T, EAST)
	var/obj/machinery/gear_dispenser/custom/custom = allocate(/obj/machinery/gear_dispenser/custom, east)
	TEST_ASSERT_EQUAL(length(custom.dispenses), length(subtypesof(/datum/gear_disp/custom)), "the custom dispenser lists every custom gear set")
	for(var/gear_name in custom.dispenses)
		TEST_ASSERT(istype(custom.dispenses[gear_name], /datum/gear_disp/custom), "and everything it lists is custom gear")

	var/obj/machinery/reagent_refinery/mixer/dq_west_probe/mixer = allocate(/obj/machinery/reagent_refinery/mixer/dq_west_probe, get_step(east, EAST))
	TEST_ASSERT_EQUAL(mixer.mixer_angle, dir2angle(WEST), "a mixer's arm starts pointing the way it faces")

// The experiment machines get their handler once they are made.
/datum/unit_test/dq_init_sweep5_experiment_handlers

/datum/unit_test/dq_init_sweep5_experiment_handlers/Run()
	var/turf/T = dq_containment_floor()
	var/obj/machinery/doppler_array/doppler = allocate(/obj/machinery/doppler_array, T)
	var/datum/experiment_handler/doppler_handler = doppler.experiment_handler
	TEST_ASSERT_NOTNULL(doppler_handler, "a doppler array has an experiment handler")
	TEST_ASSERT_EQUAL(doppler_handler.owner, doppler, "owned by it")
	TEST_ASSERT(/datum/experiment/ordnance in doppler_handler.allowed_experiments, "that runs ordnance experiments")

	var/obj/machinery/rnd/destructive_analyzer/analyzer = allocate(/obj/machinery/rnd/destructive_analyzer, get_step(T, EAST))
	var/datum/experiment_handler/analyzer_handler = analyzer.experiment_handler
	TEST_ASSERT_NOTNULL(analyzer_handler, "a destructive analyzer has an experiment handler")
	TEST_ASSERT_EQUAL(analyzer_handler.owner, analyzer, "owned by it")
	TEST_ASSERT(/datum/experiment/scanning in analyzer_handler.allowed_experiments, "that runs scanning experiments")

// A bolted-down generator takes the capacitors beside it that face it.
/datum/unit_test/dq_init_sweep5_shield_gen_capacitors

/datum/unit_test/dq_init_sweep5_shield_gen_capacitors/Run()
	var/turf/T = dq_containment_floor()
	var/turf/east = get_step(T, EAST)
	var/obj/machinery/shield_capacitor/facing = allocate(/obj/machinery/shield_capacitor, east)
	facing.set_dir(WEST)
	facing.set_anchored(TRUE)
	var/obj/machinery/shield_gen/dq_anchored_probe/gen = allocate(/obj/machinery/shield_gen/dq_anchored_probe, T)
	TEST_ASSERT_EQUAL(facing.owned_gen(), gen, "a capacitor facing a bolted-down generator feeds it")
	TEST_ASSERT(facing in gen.capacitors, "and the generator lists it")

	var/turf/west = get_step(T, WEST)
	var/obj/machinery/shield_gen/loose = allocate(/obj/machinery/shield_gen, west)
	TEST_ASSERT_NULL(loose.capacitors, "a generator that is not bolted down takes none")

// The wearable circuit cases build their assembly once the clothing is made.
/datum/unit_test/dq_init_sweep5_circuitry_clothing

/datum/unit_test/dq_init_sweep5_circuitry_clothing/Run()
	var/turf/T = dq_containment_floor()
	var/list/types = list(
		/obj/item/clothing/under/circuitry, /obj/item/clothing/gloves/circuitry, /obj/item/clothing/glasses/circuitry,
		/obj/item/clothing/shoes/circuitry, /obj/item/clothing/head/circuitry, /obj/item/clothing/ears/circuitry, /obj/item/clothing/suit/circuitry)
	for(var/path in types)
		var/obj/item/clothing/worn = allocate(path, T)
		TEST_ASSERT(istype(worn.IC, /obj/item/electronic_assembly/clothing), "[path] holds an assembly")
		TEST_ASSERT_EQUAL(worn.IC.clothing(), worn, "[path]: the assembly names the clothing it sits in")
		TEST_ASSERT_EQUAL(worn.IC.name, worn.name, "[path]: and is named for it")
		TEST_ASSERT(istype(worn.action_circuit, /obj/item/integrated_circuit/built_in/action_button), "[path] has its action circuit")
		TEST_ASSERT_EQUAL(length(worn.actions), 1, "[path] has the one action that pulses it")
	var/obj/item/clothing/ears/circuitry/ears = allocate(/obj/item/clothing/ears/circuitry, T)
	var/found_speaker = FALSE
	for(var/obj/item/integrated_circuit/built_in/earpiece_speaker/speaker in ears.IC)
		found_speaker = TRUE
	TEST_ASSERT(found_speaker, "an earpiece also has its speaker circuit")

// The telescreens' pinboards are made once the screen is, before their radio is tuned.
/datum/unit_test/dq_init_sweep5_telescreen_pinboards

/datum/unit_test/dq_init_sweep5_telescreen_pinboards/Run()
	var/turf/T = dq_containment_floor()
	var/obj/machinery/computer/security/telescreen/entertainment/entertainment = allocate(/obj/machinery/computer/security/telescreen/entertainment, T)
	TEST_ASSERT_NOTNULL(entertainment.pinboard, "an entertainment monitor has its pinboard")
	TEST_ASSERT(length(entertainment.pinboard.filters) >= 1, "cut to the screen")
	TEST_ASSERT_EQUAL(entertainment.radio.frequency, ENT_FREQ, "and its radio is tuned after")
	var/obj/machinery/computer/security/telescreen/bodycamera/body = allocate(/obj/machinery/computer/security/telescreen/bodycamera, get_step(T, EAST))
	TEST_ASSERT_NOTNULL(body.bpinboard, "a bodycamera monitor has its pinboard")
	TEST_ASSERT(length(body.bpinboard.filters) >= 1, "cut to the screen")
	TEST_ASSERT_EQUAL(body.bradio.frequency, BDCM_FREQ, "and its radio is tuned after")

// A ghost has an exonet address once it is made.
/datum/unit_test/dq_init_sweep5_ghost_exonet

/datum/unit_test/dq_init_sweep5_ghost_exonet/Run()
	var/turf/T = dq_containment_floor()
	var/mob/observer/dead/ghost = allocate(/mob/observer/dead, T)
	TEST_ASSERT_NOTNULL(ghost.exonet, "a ghost has an exonet")
	TEST_ASSERT(findtext(ghost.exonet.address, "fc00:") == 1, "with an exonet address")

// A stump takes its limb's place before the parent init and its condition before the organ's own setup.
/datum/unit_test/dq_init_sweep5_stump_condition

/datum/unit_test/dq_init_sweep5_stump_condition/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/limb = H.get_organ(BP_L_HAND)
	TEST_ASSERT(limb && limb.owner == H, "the host has a hand to replace")
	own(limb)
	var/max_damage = limb.max_damage
	limb.removed(null)
	var/obj/item/organ/external/stump/organic = allocate(/obj/item/organ/external/stump, H, null, limb)
	TEST_ASSERT_EQUAL(organic.max_damage, max_damage, "a stump takes the damage cap of its limb")
	TEST_ASSERT(!organic.is_robotic(), "and is organic when its limb is")

	var/obj/item/organ/external/second = H.get_organ(BP_R_HAND)
	TEST_ASSERT(second && second.owner == H, "the host has another hand")
	own(second)
	second.robotize()
	second.removed(null)
	var/obj/item/organ/external/stump/robotic = allocate(/obj/item/organ/external/stump, H, null, second)
	TEST_ASSERT(robotic.is_robotic(), "a stump of a robotic limb is robotic")
	TEST_ASSERT_EQUAL(robotic.max_damage, second.max_damage, "with its limb's damage cap")
