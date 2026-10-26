// A robot has no Initialize(): its number is a roll and its build steps are setup() hooks of its CAPABILITIES block, in the order the old override ran them
// (updatename, setup_radio, setup_camera, setup_brain, setup_laws, setup_module, initialize_components, setup_cell). The expected values below are what that
// override produced, read from the steps and their chassis overrides (robot.dm, component.dm, drone.dm, syndicate.dm, robot_remote_control.dm).

/// What every robot has once built: a number, parts, a cell, a radio and laws (a drone's own naming makes no PDA or communicator).
/datum/unit_test/proc/dq_robot_built_checks(mob/living/silicon/robot/R, label)
	TEST_ASSERT(R.ident >= 1 && R.ident <= 999, "[label]: its number is rolled in 1..999 ([R.ident])")
	TEST_ASSERT_EQUAL(R.real_name, R.name, "[label]: its real name is its name")
	TEST_ASSERT(istype(R.radio, /obj/item/radio/borg), "[label]: it has a borg radio")
	TEST_ASSERT_EQUAL(R.common_radio, R.radio, "[label]: whose common radio is that radio")
	TEST_ASSERT_EQUAL(length(R.components), ROBOT_SLOT_COUNT, "[label]: every part slot is built")
	for(var/slot in 1 to ROBOT_SLOT_COUNT)
		TEST_ASSERT(R.get_component(slot), "[label]: part slot [slot] holds a part")
	TEST_ASSERT(istype(R.cell, R.cell_type), "[label]: its cell is its chassis cell type ([R.cell_type])")
	TEST_ASSERT(R.laws, "[label]: it has laws")

/datum/unit_test/dq_robot_init_default

/datum/unit_test/dq_robot_init_default/Run()
	var/turf/T = dq_containment_floor()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, T)
	dq_robot_built_checks(R, "default robot")
	TEST_ASSERT_EQUAL(R.modtype, "Default", "a default robot is a Default module type")
	TEST_ASSERT_EQUAL(R.braintype, BORG_BRAINTYPE_CYBORG, "with no brain, its brain type is a cyborg's")
	TEST_ASSERT_EQUAL(R.name, "Default Cyborg-[R.ident]", "its name is its module type, brain type and number")
	TEST_ASSERT_NULL(R.mmi, "it has no brain")
	TEST_ASSERT_NULL(R.module, "and no module until one is picked")
	TEST_ASSERT(istype(R.laws, using_map.default_law_type), "its laws are the map's default set")
	TEST_ASSERT_EQUAL(R.additional_law_channels?["Binary"], "#b", "it states laws on binary")
	if(isnull(R.connected_ai))
		TEST_ASSERT(!R.lawupdate, "with no AI to follow, it stops syncing laws")
	TEST_ASSERT(istype(R.camera, /obj/machinery/camera), "it has a machinery camera")
	TEST_ASSERT_EQUAL(R.camera.c_tag, R.real_name, "tagged with its name")
	TEST_ASSERT((NETWORK_ROBOTS in R.camera.network) && (NETWORK_DEFAULT in R.camera.network), "on the default and robots networks")
	TEST_ASSERT(istype(R.aiCamera, R.photo_camera_type), "and a photo camera of its chassis type")
	TEST_ASSERT(istype(R.cell, /obj/item/cell/robot_station), "its cell is the station robot cell")
	TEST_ASSERT(R.rbPDA && R.communicator, "it has a PDA and a communicator, named with it")
	TEST_ASSERT(granted(R, robot_naming()), "a robot its player may name has the pick-name ability")

/datum/unit_test/dq_robot_init_drone

/datum/unit_test/dq_robot_init_drone/Run()
	var/turf/T = dq_containment_floor()
	var/mob/living/silicon/robot/drone/D = allocate(/mob/living/silicon/robot/drone, T)
	dq_robot_built_checks(D, "drone")
	TEST_ASSERT_EQUAL(D.name, "[initial(D.name)] ([D.serial_number])", "a drone is named after its rolled serial number")
	TEST_ASSERT(istype(D.laws, /datum/ai_laws/drone), "its laws are its law type")
	TEST_ASSERT_NULL(D.additional_law_channels?["Binary"], "it does not state laws on binary")
	TEST_ASSERT_EQUAL(D.additional_law_channels?["Drone"], ":d", "it states them on the drone channel")
	TEST_ASSERT(istype(D.module, /obj/item/robot_module/drone), "it has the drone module")
	TEST_ASSERT(istype(D.cell, /obj/item/cell/high), "its cell is the better drone battery")
	TEST_ASSERT(istype(D.aiCamera, /obj/item/camera/siliconcam/drone_camera), "its photo camera is the drone's")
	TEST_ASSERT(findtext(D.bio.flavor_text, "repair drone"), "its flavour text is the repair drone's")
	TEST_ASSERT(GLOB.all_languages[LANGUAGE_DRONE_TALK] in D.languages, "it speaks drone talk")

	var/mob/living/silicon/robot/drone/construction/C = allocate(/mob/living/silicon/robot/drone/construction, T)
	TEST_ASSERT(istype(C.laws, /datum/ai_laws/construction_drone), "a construction drone has its own laws")
	TEST_ASSERT(istype(C.module, /obj/item/robot_module/drone/construction), "and module")
	TEST_ASSERT(findtext(C.bio.flavor_text, "bulky construction drone"), "and flavour text")
	TEST_ASSERT_EQUAL(C.name, "[initial(C.name)] ([C.serial_number])", "and its name follows its type")

/datum/unit_test/dq_robot_init_syndicate

/datum/unit_test/dq_robot_init_syndicate/Run()
	var/turf/T = dq_containment_floor()
	var/mob/living/silicon/robot/syndicate/S = allocate(/mob/living/silicon/robot/syndicate, T)
	dq_robot_built_checks(S, "syndicate")
	TEST_ASSERT(istype(S.mmi, /obj/item/mmi/digital/robot), "a syndicate borg has a drone brain")
	TEST_ASSERT_EQUAL(S.braintype, BORG_BRAINTYPE_DRONE, "so its brain type is a drone's")
	TEST_ASSERT_EQUAL(S.name, "Syndicate Drone-[S.ident]", "its name was made after the brain went in")
	TEST_ASSERT(istype(S.laws, /datum/ai_laws/syndicate_override), "its laws are the syndicate override")
	TEST_ASSERT(istype(S.radio.keyslot, /obj/item/encryptionkey/syndicate), "its radio carries the syndicate key")
	TEST_ASSERT_NULL(S.camera, "it has no machinery camera: its codes are scrambled")
	TEST_ASSERT(istype(S.aiCamera, S.photo_camera_type), "but it has a photo camera")
	TEST_ASSERT(istype(S.cell, /obj/item/cell/robot_syndi), "its cell is the syndicate cell")
	TEST_ASSERT(!S.lawupdate, "it never syncs laws")
	TEST_ASSERT_NULL(S.module, "a plain syndicate borg has no module yet")
	TEST_ASSERT_EQUAL(S.restrict_modules_to, GLOB.antag_module_types, "but may pick from the antag modules")

	var/mob/living/silicon/robot/syndicate/protector/P = allocate(/mob/living/silicon/robot/syndicate/protector, T)
	dq_robot_built_checks(P, "protector")
	TEST_ASSERT(istype(P.module, /obj/item/robot_module/robot/syndicate/protector), "a protector has its module")
	TEST_ASSERT_EQUAL(P.modtype, "Protector", "and its module type")
	TEST_ASSERT(length(P.restrict_modules_to) == 1 && P.restrict_modules_to[1] == "Protector", "and may pick nothing else")
	TEST_ASSERT_EQUAL(P.name, "Syndicate Drone-[P.ident]", "its name was made before the module type was set, as before")

/datum/unit_test/dq_robot_init_shell

/datum/unit_test/dq_robot_init_shell/Run()
	var/turf/T = dq_containment_floor()
	var/mob/living/silicon/robot/ai_shell/A = allocate(/mob/living/silicon/robot/ai_shell, T)
	dq_robot_built_checks(A, "AI shell")
	TEST_ASSERT(istype(A.mmi, /obj/item/mmi/inert/ai_remote), "a premade shell has the AI remote interface for a brain")
	TEST_ASSERT(A.shell, "so it is a shell")
	TEST_ASSERT_EQUAL(A.braintype, "AI Shell", "its brain type says so")
	TEST_ASSERT_EQUAL(A.real_name, "Default AI Shell [A.ident]", "and its name is its module type, AI Shell and number")
	TEST_ASSERT(istype(A.rbPDA, /obj/item/pda/ai/shell), "its PDA is the shell's")
