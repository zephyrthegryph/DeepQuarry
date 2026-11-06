// The exosuit's window buttons, through the input inbox: the pilot's reach the controls, a stranger's do nothing. These read the same for an op.

/datum/unit_test/dq_topic_mecha_panel

/datum/unit_test/dq_topic_mecha_panel/Run()
	var/turf/T = test_floor()
	var/obj/mecha/working/ripley/mech = allocate(/obj/mecha/working/ripley, T)
	var/mob/living/carbon/human/pilot = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/stranger = allocate(/mob/living/carbon/human)
	TEST_ASSERT(move_into(mech, MECHA_SLOT_PILOT, pilot), "the pilot gets in")
	// the pilot's controls
	var/lights_before = mech.lights
	own(test_ui(pilot, mech, "toggle_lights"))
	TEST_ASSERT(mech.lights != lights_before, "the pilot's lights button toggles the lights")
	var/mic_before = mech.radio.broadcasting
	own(test_ui(pilot, mech, "rmictoggle"))
	TEST_ASSERT(mech.radio.broadcasting != mic_before, "the pilot's microphone button toggles the radio")
	var/spk_before = mech.radio.listening
	own(test_ui(pilot, mech, "rspktoggle"))
	TEST_ASSERT(mech.radio.listening != spk_before, "the pilot's speaker button toggles the radio")
	var/lock_before = mech.add_req_access
	own(test_ui(pilot, mech, "toggle_id_upload"))
	TEST_ASSERT(mech.add_req_access != lock_before, "the pilot's ID upload button toggles the panel")
	own(test_ui(pilot, mech, "dna_lock"))
	TEST_ASSERT_EQUAL(mech.dna, pilot.dna?.unique_enzymes, "the pilot's DNA lock button keys the suit to their DNA")
	own(test_ui(pilot, mech, "reset_dna"))
	TEST_ASSERT_NULL(mech.dna, "the reset button clears it")
	// a number from the button crosses as a number; the frequency moves by it
	var/freq_before = mech.radio.frequency
	own(test_ui(pilot, mech, "rfreq", list("delta" = 2)))
	TEST_ASSERT_EQUAL(mech.radio.frequency, sanitize_frequency(freq_before + 2), "the frequency button moves the radio by its delta")
	// someone who is not the pilot does nothing
	lights_before = mech.lights
	own(test_ui(stranger, mech, "toggle_lights"))
	TEST_ASSERT_EQUAL(mech.lights, lights_before, "a stranger's lights button does nothing")
	mic_before = mech.radio.broadcasting
	own(test_ui(stranger, mech, "rmictoggle"))
	TEST_ASSERT_EQUAL(mech.radio.broadcasting, mic_before, "a stranger's microphone button does nothing")
	own(test_ui(stranger, mech, "dna_lock"))
	TEST_ASSERT_NULL(mech.dna, "a stranger cannot lock the suit to their DNA")
	freq_before = mech.radio.frequency
	own(test_ui(stranger, mech, "rfreq", list("delta" = 2)))
	TEST_ASSERT_EQUAL(mech.radio.frequency, freq_before, "a stranger cannot move the frequency")

/// The window is the exosuit's own, through the real tgui state: the pilot keeps it, a stranger far away does not, an unconscious pilot cannot work it.
/datum/unit_test/dq_topic_mecha_window_state

/datum/unit_test/dq_topic_mecha_window_state/Run()
	var/turf/T = test_floor()
	var/obj/mecha/working/ripley/mech = allocate(/obj/mecha/working/ripley, T)
	var/mob/living/carbon/human/dq_tgui_transport/pilot = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	pilot.enable_godmode()
	var/mob/living/carbon/human/dq_tgui_transport/far = allocate(/mob/living/carbon/human/dq_tgui_transport, run_loc_floor_top_right)
	far.enable_godmode()
	TEST_ASSERT(move_into(mech, MECHA_SLOT_PILOT, pilot), "the pilot gets in")
	TEST_ASSERT_EQUAL(mech.tgui_status(pilot, mech.tgui_state(pilot)), STATUS_INTERACTIVE, "the pilot works the window")
	own(test_ui(pilot, mech, "toggle_lights"))
	TEST_ASSERT_EQUAL(mech.tgui_status(pilot, mech.tgui_state(pilot)), STATUS_INTERACTIVE, "the window is still open after a press")
	TEST_ASSERT(mech.tgui_status(far, mech.tgui_state(far)) < STATUS_INTERACTIVE, "someone far from the suit cannot work it")
	pilot.set_stat(UNCONSCIOUS)
	TEST_ASSERT(mech.tgui_status(pilot, mech.tgui_state(pilot)) < STATUS_INTERACTIVE, "an unconscious pilot cannot work it")

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
	// selecting names equipment by its handle, and only equipment mounted on this suit is found
	own(test_ui(pilot, mech, "select_equip", list("id" = ref_token(jet))))
	TEST_ASSERT_EQUAL(mech.selected, jet, "the pilot selects mounted equipment by its handle")
	var/obj/item/mecha_parts/mecha_equipment/before = mech.selected
	own(test_ui(pilot, mech, "select_equip", list("id" = ref_token(loose))))
	TEST_ASSERT_EQUAL(mech.selected, before, "equipment that is not mounted on this suit cannot be selected")
	own(test_ui(pilot, mech, "select_equip", list("id" = "not a handle")))
	TEST_ASSERT_EQUAL(mech.selected, before, "and a made-up handle names nothing")
	// the window lists the equipment with the buttons it offers
	var/list/data = hc_data(mech, pilot)
	var/list/entry
	for(var/list/E in data["equipment"])
		if(E["id"] == ref_token(jet))
			entry = E
	TEST_ASSERT_NOTNULL(entry, "the window lists the jetpack")
	TEST_ASSERT_EQUAL(entry["name"], jet.name, "with its name")
	TEST_ASSERT(entry["selected"], "and says it is the selected one")
	TEST_ASSERT_EQUAL(length(entry["controls"]), 1, "and its one button")
	// the equipment's own buttons: the pilot's reach them, a stranger's do not
	own(test_ui(stranger, mech, "equip_control", list("id" = ref_token(jet), "control" = "toggle")))
	TEST_ASSERT_NULL(mech.active_jetpack, "a stranger cannot switch the jetpack on")
	own(test_ui(pilot, mech, "equip_control", list("id" = ref_token(jet), "control" = "no such button")))
	TEST_ASSERT_NULL(mech.active_jetpack, "a button the equipment does not offer does nothing")
	own(test_ui(pilot, mech, "equip_control", list("id" = ref_token(loose), "control" = "toggle")))
	TEST_ASSERT_NULL(loose.chassis, "equipment that is not mounted has no buttons here")
	own(test_ui(pilot, mech, "equip_control", list("id" = ref_token(jet), "control" = "toggle")))
	TEST_ASSERT_EQUAL(mech.active_jetpack, jet, "the pilot's jetpack button switches it on")
	own(test_ui(pilot, mech, "equip_control", list("id" = ref_token(jet), "control" = "toggle")))
	TEST_ASSERT_NULL(mech.active_jetpack, "and off again")
	own(test_ui(stranger, mech, "detach_equipment", list("id" = ref_token(jet))))
	TEST_ASSERT_EQUAL(jet.chassis, mech, "a stranger cannot detach equipment")
	own(test_ui(pilot, mech, "detach_equipment", list("id" = ref_token(jet))))
	TEST_ASSERT_NULL(jet.chassis, "the pilot's detach button takes it off the suit")

/// The readouts and buttons the old equipment line showed, now data: a mode button carries its number, a reel offers its buttons only with cable on it.
/datum/unit_test/dq_topic_mecha_equipment_controls

/datum/unit_test/dq_topic_mecha_equipment_controls/Run()
	var/turf/T = test_floor()
	var/obj/mecha/working/ripley/mech = allocate(/obj/mecha/working/ripley, T)
	var/mob/living/carbon/human/pilot = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT(move_into(mech, MECHA_SLOT_PILOT, pilot), "the pilot gets in")
	var/obj/item/mecha_parts/mecha_equipment/gravcatapult/catapult = allocate(/obj/item/mecha_parts/mecha_equipment/gravcatapult, T)
	var/obj/item/mecha_parts/mecha_equipment/tool/cable_layer/layer = allocate(/obj/item/mecha_parts/mecha_equipment/tool/cable_layer, T)
	var/obj/item/mecha_parts/mecha_equipment/generator/gen = allocate(/obj/item/mecha_parts/mecha_equipment/generator, T)
	catapult.attach(mech)
	layer.attach(mech)
	gen.attach(mech)
	// the catapult: sling or push
	TEST_ASSERT_EQUAL(catapult.mode, 1, "the catapult starts slinging")
	TEST_ASSERT(length(catapult.equip_info_lines()), "it reads out its mode")
	own(test_ui(pilot, mech, "equip_control", list("id" = ref_token(catapult), "control" = "push")))
	TEST_ASSERT_EQUAL(catapult.mode, 2, "the push button sets the mode")
	own(test_ui(pilot, mech, "equip_control", list("id" = ref_token(catapult), "control" = "sling")))
	TEST_ASSERT_EQUAL(catapult.mode, 1, "and the sling button sets it back")
	// the cable reel: no buttons while it is empty
	TEST_ASSERT_EQUAL(length(layer.equip_controls()), 0, "an empty reel offers no buttons")
	TEST_ASSERT(("Cable: 0 m" in layer.equip_info_lines()), "and reads out its length")
	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil, T, 20)
	TEST_ASSERT_EQUAL(layer.load_cable(coil), 20, "the reel takes the cable")
	TEST_ASSERT_EQUAL(length(layer.equip_controls()), 2, "a loaded reel offers to switch on and to cut")
	TEST_ASSERT(("Cable: 20 m" in layer.equip_info_lines()), "and reads out its length")
	var/was_ready = layer.equip_ready
	own(test_ui(pilot, mech, "equip_control", list("id" = ref_token(layer), "control" = "toggle")))
	TEST_ASSERT(layer.equip_ready != was_ready, "the reel's switch toggles it")
	// the generator: its fuel is a readout and its switch toggles it
	TEST_ASSERT(length(gen.equip_info_lines()), "the generator reads out its fuel")
	var/gen_before = gen.generating
	own(test_ui(pilot, mech, "equip_control", list("id" = ref_token(gen), "control" = "toggle")))
	TEST_ASSERT(gen.generating != gen_before, "the generator's switch toggles it")
	// the window carries all of it
	var/list/data = hc_data(mech, pilot)
	TEST_ASSERT_EQUAL(length(data["equipment"]), 3, "the window lists the three pieces")

/// A mode button sends its number (the RCD's modes, the micro shotgun's shells): only a number the equipment offers is taken.
/datum/unit_test/dq_topic_mecha_equipment_modes

/datum/unit_test/dq_topic_mecha_equipment_modes/Run()
	var/turf/T = test_floor()
	var/obj/mecha/working/ripley/mech = allocate(/obj/mecha/working/ripley, T)
	var/mob/living/carbon/human/pilot = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT(move_into(mech, MECHA_SLOT_PILOT, pilot), "the pilot gets in")
	var/obj/item/mecha_parts/mecha_equipment/tool/rcd/rcd = allocate(/obj/item/mecha_parts/mecha_equipment/tool/rcd, T)
	rcd.attach(mech)
	var/list/controls = rcd.equip_controls()
	TEST_ASSERT(length(controls) >= 2, "the RCD offers a button for each of its modes")
	var/list/last = controls[length(controls)]
	own(test_ui(pilot, mech, "equip_control", list("id" = ref_token(rcd), "control" = "mode", "value" = last["value"])))
	TEST_ASSERT_EQUAL(rcd.my_rcd.mode_index, last["value"], "a mode button sets the RCD's mode")
	var/mode = rcd.my_rcd.mode_index
	own(test_ui(pilot, mech, "equip_control", list("id" = ref_token(rcd), "control" = "mode", "value" = length(controls) + 5)))
	TEST_ASSERT_EQUAL(rcd.my_rcd.mode_index, mode, "a mode the RCD does not have is not taken")

/// The mounted sleeper's window: the occupant and the buttons the old line offered, an injection from the syringe gun's reagents named by their id,
/// and the window itself held by the pilot through the real tgui state.
/datum/unit_test/dq_topic_mecha_sleeper

/datum/unit_test/dq_topic_mecha_sleeper/Run()
	var/turf/T = test_floor()
	var/obj/mecha/medical/odysseus/mech = allocate(/obj/mecha/medical/odysseus, T)
	var/mob/living/carbon/human/dq_tgui_transport/pilot = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	pilot.enable_godmode()
	var/mob/living/carbon/human/patient = allocate(/mob/living/carbon/human, T)
	var/obj/item/mecha_parts/mecha_equipment/tool/sleeper/sleeper = allocate(/obj/item/mecha_parts/mecha_equipment/tool/sleeper, T)
	var/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/gun = allocate(/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun, T)
	sleeper.attach(mech)
	gun.attach(mech)
	TEST_ASSERT(move_into(mech, MECHA_SLOT_PILOT, pilot), "the pilot gets in")
	TEST_ASSERT_EQUAL(length(sleeper.equip_controls()), 1, "an empty sleeper offers its window and nothing to eject")
	TEST_ASSERT_EQUAL(length(sleeper.equip_info_lines()), 0, "and no occupant line")
	TEST_ASSERT(move_into(sleeper, OCCUPANT_SLOT_MECHA_SLEEPER, patient), "a patient is loaded")
	TEST_ASSERT_EQUAL(length(sleeper.equip_controls()), 2, "a loaded sleeper offers to show the stats and to eject")
	TEST_ASSERT_EQUAL(length(sleeper.equip_info_lines()), 1, "and names its occupant")
	TEST_ASSERT_EQUAL(sleeper.tgui_status(pilot, sleeper.tgui_state(pilot)), STATUS_INTERACTIVE, "the pilot works the sleeper's window")
	gun.reagents.add_reagent(REAGENT_ID_INAPROVALINE, 20)
	var/list/data = hc_data(sleeper, pilot)
	TEST_ASSERT(data["has_occupant"], "the window shows the occupant")
	TEST_ASSERT_EQUAL(data["occupant_name"], patient.name, "by name")
	var/list/offered = data["injectables"]
	TEST_ASSERT_EQUAL(length(offered), 1, "the gun's one reagent is offered")
	var/list/row = offered[1]
	TEST_ASSERT_EQUAL(row["id"], REAGENT_ID_INAPROVALINE, "by its id")
	own(test_ui(pilot, sleeper, "inject", list("reagent" = "no such reagent")))
	TEST_ASSERT_EQUAL(patient.reagents.get_reagent_amount(REAGENT_ID_INAPROVALINE), 0, "a reagent the gun does not hold is not injected")
	own(test_ui(pilot, sleeper, "inject", list("reagent" = REAGENT_ID_INAPROVALINE)))
	TEST_ASSERT(patient.reagents.get_reagent_amount(REAGENT_ID_INAPROVALINE) > 0, "the offered reagent is injected")
	TEST_ASSERT_EQUAL(sleeper.tgui_status(pilot, sleeper.tgui_state(pilot)), STATUS_INTERACTIVE, "the window is still open after a press")
	own(test_ui(pilot, mech, "equip_control", list("id" = ref_token(sleeper), "control" = "eject")))
	TEST_ASSERT_NULL(sleeper.slot_item(OCCUPANT_SLOT_MECHA_SLEEPER), "the exosuit window's eject button lets the patient out")

/// The syringe gun: its readouts and buttons in the exosuit's window, its own window's reagents named by id, the purge buttons.
/datum/unit_test/dq_topic_mecha_syringe_gun

/datum/unit_test/dq_topic_mecha_syringe_gun/Run()
	var/turf/T = test_floor()
	var/obj/mecha/medical/odysseus/mech = allocate(/obj/mecha/medical/odysseus, T)
	var/mob/living/carbon/human/dq_tgui_transport/pilot = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	pilot.enable_godmode()
	var/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun/gun = allocate(/obj/item/mecha_parts/mecha_equipment/tool/syringe_gun, T)
	gun.attach(mech)
	TEST_ASSERT(move_into(mech, MECHA_SLOT_PILOT, pilot), "the pilot gets in")
	TEST_ASSERT_EQUAL(length(gun.equip_controls()), 2, "the gun offers its mode switch and its reagent list")
	TEST_ASSERT_EQUAL(length(gun.equip_info_lines()), 2, "and reads out its mode, its syringes and its reagents")
	var/mode = gun.mode
	own(test_ui(pilot, mech, "equip_control", list("id" = ref_token(gun), "control" = "toggle_mode")))
	TEST_ASSERT(gun.mode != mode, "the mode button switches launching and analysing")
	TEST_ASSERT_EQUAL(gun.tgui_status(pilot, gun.tgui_state(pilot)), STATUS_INTERACTIVE, "the pilot works the gun's window")
	gun.reagents.add_reagent(REAGENT_ID_INAPROVALINE, 10)
	gun.reagents.add_reagent(REAGENT_ID_ANTITOXIN, 10)
	var/list/data = hc_data(gun, pilot)
	TEST_ASSERT_EQUAL(length(data["current_reagents"]), 2, "the window lists the reagents it holds")
	own(test_ui(pilot, gun, "purge_reagent", list("id" = REAGENT_ID_INAPROVALINE)))
	TEST_ASSERT_EQUAL(gun.reagents.get_reagent_amount(REAGENT_ID_INAPROVALINE), 0, "the purge button clears one reagent")
	TEST_ASSERT(gun.reagents.get_reagent_amount(REAGENT_ID_ANTITOXIN) > 0, "and leaves the other")
	own(test_ui(pilot, gun, "purge_all"))
	TEST_ASSERT_EQUAL(gun.reagents.total_volume, 0, "the purge-all button clears them all")
	TEST_ASSERT_EQUAL(gun.tgui_status(pilot, gun.tgui_state(pilot)), STATUS_INTERACTIVE, "the window is still open after a press")

/// A person the CanUseObjTopic gate refuses, as a borg or AI without the right ID is: the window's real tgui state still runs (a transport has no client
/// to close it).
/mob/living/carbon/human/dq_tgui_transport/denied_obj

/mob/living/carbon/human/dq_tgui_transport/denied_obj/CanUseObjTopic(obj/O)
	return 0

/// The maintenance window actions keep the names the window sends (maint_protocol, maint_set_air, maint_remove_passenger) and each keeps its guards:
/// protocols on and the actor next to the suit for the bolts, the bolts exposed for the valve and the hatch, a passenger to pull out.
/datum/unit_test/dq_topic_mecha_maintenance_actions

/datum/unit_test/dq_topic_mecha_maintenance_actions/Run()
	test_driver_begin()
	exercise_maintenance()
	test_driver_end()

/datum/unit_test/dq_topic_mecha_maintenance_actions/proc/exercise_maintenance()
	var/turf/T = test_floor()
	var/obj/mecha/working/ripley/mech = allocate(/obj/mecha/working/ripley, T)
	var/mob/living/carbon/human/dq_tgui_transport/tech = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	tech.enable_godmode()
	TEST_ASSERT_EQUAL(mech.tgui_status(tech, mech.tgui_state(tech)), STATUS_INTERACTIVE, "a conscious person next to the suit works its window")
	// maint_protocol: the bolts, only with the protocols on
	mech.set_state(MECHA_OPERATING)
	mech.set_maint_access(0)
	own(test_ui(tech, mech, "maint_protocol"))
	TEST_ASSERT_EQUAL(mech.state, MECHA_OPERATING, "with the protocols off the bolts button does nothing")
	mech.set_maint_access(1)
	own(test_ui(tech, mech, "maint_protocol"))
	TEST_ASSERT_EQUAL(mech.state, MECHA_BOLTS_SECURED, "with the protocols on the bolts button exposes the bolts")
	own(test_ui(tech, mech, "maint_protocol"))
	TEST_ASSERT_EQUAL(mech.state, MECHA_OPERATING, "and presses again to hide them")
	var/mob/living/carbon/human/dq_tgui_transport/far = allocate(/mob/living/carbon/human/dq_tgui_transport, run_loc_floor_top_right)
	far.enable_godmode()
	own(test_ui(far, mech, "maint_protocol"))
	TEST_ASSERT_EQUAL(mech.state, MECHA_OPERATING, "someone not next to the suit cannot work the bolts")
	// maint_set_air: bolts exposed, then a pressure
	own(test_ui(tech, mech, "maint_set_air"))
	TEST_ASSERT_NULL(SSrequests.open_for(tech), "with the bolts hidden the valve button asks nothing")
	mech.set_state(MECHA_BOLTS_SECURED)
	own(test_ui(tech, mech, "maint_set_air"))
	TEST_ASSERT(istype(SSrequests.open_for(tech), /datum/prompt/number/mecha_tank_valve), "with the bolts exposed the valve button asks for a pressure")
	test_answer(tech, 88)
	test_time(0.1 SECONDS)
	TEST_ASSERT_EQUAL(mech.internal_tank_valve, 88, "the answer sets the valve")
	// maint_remove_passenger: needs a passenger and the bolts exposed
	own(test_ui(tech, mech, "maint_remove_passenger"))
	TEST_ASSERT_NULL(SSrequests.open_for(tech), "with nobody in a compartment the hatch button asks nothing")
	var/obj/item/mecha_parts/mecha_equipment/tool/passenger/P = allocate(/obj/item/mecha_parts/mecha_equipment/tool/passenger, T)
	var/mob/living/carbon/human/rider = allocate(/mob/living/carbon/human, T)
	P.attach(mech)
	TEST_ASSERT(move_into(P, OCCUPANT_SLOT_MECHA_PASSENGER, rider), "a passenger takes the compartment")
	mech.set_state(MECHA_OPERATING)
	own(test_ui(tech, mech, "maint_remove_passenger"))
	TEST_ASSERT_NULL(SSrequests.open_for(tech), "with the bolts hidden the hatch button asks nothing")
	mech.set_state(MECHA_BOLTS_SECURED)
	own(test_ui(tech, mech, "maint_remove_passenger"))
	TEST_ASSERT(istype(SSrequests.open_for(tech), /datum/prompt/choice/mecha_remove_passenger), "with a passenger and the bolts exposed the hatch button asks which one")
	test_answer(tech, "[rider]")
	test_time(5 SECONDS)
	TEST_ASSERT_NULL(P.slot_item(OCCUPANT_SLOT_MECHA_PASSENGER), "the answer pulls the passenger out once the hatch is open")

/// The old href gate, kept on the buttons that need no pilot: a conscious pilot always reaches them, anyone else must pass CanUseObjTopic() (the
/// ID-access check a borg or AI gets against the suit).
/datum/unit_test/dq_topic_mecha_access_requirement

/datum/unit_test/dq_topic_mecha_access_requirement/Run()
	var/turf/T = test_floor()
	var/obj/mecha/working/ripley/mech = allocate(/obj/mecha/working/ripley, T)
	var/mob/living/carbon/human/dq_tgui_transport/ordinary = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	ordinary.enable_godmode()
	var/mob/living/carbon/human/dq_tgui_transport/denied_obj/denied = allocate(/mob/living/carbon/human/dq_tgui_transport/denied_obj, T)
	denied.enable_godmode()
	var/mob/living/silicon/robot/borg = allocate(/mob/living/silicon/robot, T)
	borg.enable_godmode()
	mech.set_maint_access(1)
	mech.set_state(MECHA_OPERATING)
	var/datum/act/op/A = take(/datum/act/op)
	A.holder = mech
	A.target = mech
	A.actor = ordinary
	TEST_ASSERT_NULL(mech.actor_reaches(A), "an ordinary person reaches the suit's buttons")
	A.actor = denied
	TEST_ASSERT_EQUAL(mech.actor_reaches(A), MSG(op/topic_gate), "a person CanUseObjTopic refuses does not")
	A.actor = borg
	TEST_ASSERT_NULL(mech.actor_reaches(A), "a borg passes where the suit's own check_access takes no list, as before")
	ordinary.set_stat(UNCONSCIOUS)
	A.actor = ordinary
	TEST_ASSERT_EQUAL(mech.actor_reaches(A), MSG(op/topic_gate), "an unconscious person does not")
	ordinary.set_stat(CONSCIOUS)
	A.actor = null
	TEST_ASSERT_EQUAL(mech.actor_reaches(A), MSG(op/topic_gate), "nobody does not")
	A.release()
	// the buttons themselves
	mech.set_add_req_access(1)
	own(test_ui(denied, mech, "access_finish"))
	TEST_ASSERT_EQUAL(mech.add_req_access, 1, "a refused person's access button does nothing")
	own(test_ui(denied, mech, "maint_protocol"))
	TEST_ASSERT_EQUAL(mech.state, MECHA_OPERATING, "a refused person's bolts button does nothing")
	mech.set_state(MECHA_BOLTS_SECURED)
	own(test_ui(denied, mech, "maint_set_air"))
	own(test_ui(denied, mech, "maint_remove_passenger"))
	TEST_ASSERT_NULL(SSrequests.open_for(denied), "and its valve and hatch buttons ask nothing")
	mech.set_state(MECHA_OPERATING)
	own(test_ui(borg, mech, "access_finish"))
	TEST_ASSERT_EQUAL(mech.add_req_access, 0, "a borg's access button works")
	mech.set_add_req_access(1)
	own(test_ui(ordinary, mech, "access_finish"))
	TEST_ASSERT_EQUAL(mech.add_req_access, 0, "an ordinary person's access button works")
	// the pilot's exception: boards, then reaches the buttons CanUseObjTopic would refuse
	mech.set_add_req_access(1)
	TEST_ASSERT(move_into(mech, MECHA_SLOT_PILOT, denied), "the refused person boards")
	own(test_ui(denied, mech, "access_finish"))
	TEST_ASSERT_EQUAL(mech.add_req_access, 0, "a pilot reaches the access button whatever CanUseObjTopic says")
	// the pilot-only buttons stay the pilot's
	var/lights = mech.lights
	own(test_ui(ordinary, mech, "toggle_lights"))
	TEST_ASSERT_EQUAL(mech.lights, lights, "a non-pilot's lights button does nothing")
	own(test_ui(denied, mech, "toggle_lights"))
	TEST_ASSERT(mech.lights != lights, "the pilot's lights button works")

/// The fighter's landing gear and the hoverpod's stabilizer buttons are the pilot's: a bystander at the window changes nothing.
/datum/unit_test/dq_topic_mecha_special_buttons

/datum/unit_test/dq_topic_mecha_special_buttons/Run()
	var/turf/T = test_floor()
	var/obj/mecha/combat/fighter/fighter = allocate(/obj/mecha/combat/fighter, T)
	var/obj/mecha/working/hoverpod/pod = allocate(/obj/mecha/working/hoverpod, T)
	var/mob/living/carbon/human/dq_tgui_transport/bystander = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	bystander.enable_godmode()
	var/mob/living/carbon/human/dq_tgui_transport/pilot_a = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	pilot_a.enable_godmode()
	var/mob/living/carbon/human/dq_tgui_transport/pilot_b = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	pilot_b.enable_godmode()
	TEST_ASSERT(move_into(fighter, MECHA_SLOT_PILOT, pilot_a), "the fighter pilot gets in")
	TEST_ASSERT(move_into(pod, MECHA_SLOT_PILOT, pilot_b), "the hoverpod pilot gets in")
	var/gear = fighter.landing_gear_raised
	own(test_ui(bystander, fighter, "toggle_landing_gear"))
	TEST_ASSERT_EQUAL(fighter.landing_gear_raised, gear, "a bystander's landing gear button does nothing")
	own(test_ui(pilot_a, fighter, "toggle_landing_gear"))
	TEST_ASSERT(fighter.landing_gear_raised != gear, "the pilot's landing gear button works")
	var/stable = pod.stabilization_enabled
	own(test_ui(bystander, pod, "toggle_stabilization"))
	TEST_ASSERT_EQUAL(pod.stabilization_enabled, stable, "a bystander's stabilizer button does nothing")
	own(test_ui(pilot_b, pod, "toggle_stabilization"))
	TEST_ASSERT(pod.stabilization_enabled != stable, "the pilot's stabilizer button works")
