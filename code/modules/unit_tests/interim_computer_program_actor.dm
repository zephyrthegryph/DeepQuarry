/// Real processor and drive; only the native window-opening boundary is observed.
/obj/item/modular_computer/interim_program_actor
	hardware_flag = PROGRAM_LAPTOP
	var/window_actor_ref
	var/window_requests = 0

/obj/item/modular_computer/interim_program_actor/install_default_hardware()
	. = ..()
	install_hardware(new /obj/item/computer_hardware/processor_unit/small(src))
	install_hardware(new /obj/item/computer_hardware/hard_drive(src))

/obj/item/modular_computer/interim_program_actor/tgui_interact(mob/user, datum/tgui/ui)
	window_actor_ref = user ? REF(user) : null
	window_requests++

/datum/computer_file/program/interim_program_actor
	filename = "interim_program_actor"
	required_access = ACCESS_ENGINE
	var/run_actor_ref
	var/start_calls = 0

/datum/computer_file/program/interim_program_actor/run_program(mob/living/user)
	run_actor_ref = user ? REF(user) : null
	start_calls++
	return ..()

/datum/unit_test/proc/interim_computer_actor_card(mob/living/carbon/human/user, turf/T)
	var/obj/item/card/id/card = allocate(/obj/item/card/id, T)
	card.access = list(ACCESS_ENGINE)
	TEST_ASSERT(user.put_in_active_hand(card), "the actual actor holds an engineering access card")
	TEST_ASSERT_EQUAL(user.GetIdCard(), card, "the real access API resolves the actor's held ID")
	return TRUE

/datum/unit_test/interim_computer_program_actor/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/unauthorized = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT(interim_computer_actor_card(actor, T), "the real actor is authorized")
	var/obj/item/modular_computer/interim_program_actor/computer = allocate(/obj/item/modular_computer/interim_program_actor, T)
	var/datum/computer_file/program/interim_program_actor/program = allocate(/datum/computer_file/program/interim_program_actor)
	TEST_ASSERT(computer.hard_drive.store_file(program), "the real drive stores the executable")
	TEST_ASSERT(computer.hard_drive.check_functionality(), "the real drive is enabled and intact")
	TEST_ASSERT_EQUAL(computer.hard_drive.holder2(), computer, "the real hardware installer associates the drive with its computer")
	TEST_ASSERT_EQUAL(computer.hard_drive.find_file_by_name(program.filename), program, "the actual drive lookup retrieves the stored executable")
	TEST_ASSERT(program.is_supported_by_hardware(computer.hardware_flag), "the actual executable supports this computer hardware")
	TEST_ASSERT_EQUAL(owner_of(program), computer.hard_drive, "the executable belongs to its actual drive")
	test_op_handler(computer, "ui_act_pc_runprogram", unauthorized, null, program.filename)
	TEST_ASSERT_EQUAL(program.run_actor_ref, REF(unauthorized), "the real run path checks the explicitly supplied unauthorized actor")
	TEST_ASSERT_EQUAL(program.program_state, PROGRAM_STATE_KILLED, "the real access check prevents unauthorized startup")
	TEST_ASSERT_NULL(computer.active_program(), "refused startup leaves no foreground program")
	test_op_handler(computer, "ui_act_pc_runprogram", actor, null, program.filename)
	TEST_ASSERT_EQUAL(program.run_actor_ref, REF(actor), "the real UI run path forwards its actual actor")
	TEST_ASSERT_EQUAL(program.start_calls, 2, "each actual UI request reaches the real program startup once")
	TEST_ASSERT_EQUAL(program.program_state, PROGRAM_STATE_ACTIVE, "the real authorized startup activates the executable")
	TEST_ASSERT_EQUAL(computer.active_program(), program, "the real computer installs the executable as its foreground program")
	test_op_handler(computer, "ui_act_pc_exit", actor)
	TEST_ASSERT_EQUAL(program.program_state, PROGRAM_STATE_KILLED, "the real quit path kills its foreground executable")
	TEST_ASSERT_NULL(computer.active_program(), "the real quit path clears the foreground program relation")
	TEST_ASSERT_EQUAL(computer.window_requests, 0, "quit does not request a window before its real timer fires")
	test_time(0.2 SECONDS)
	TEST_ASSERT_EQUAL(computer.window_requests, 1, "the real deferred quit path requests one main-menu window")
	TEST_ASSERT_EQUAL(computer.window_actor_ref, REF(actor), "the real timer retains the actual quitting actor")

/datum/unit_test/interim_computer_autorun_actor/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT(interim_computer_actor_card(actor, T), "the real startup actor is authorized")
	var/obj/item/modular_computer/interim_program_actor/computer = allocate(/obj/item/modular_computer/interim_program_actor, T)
	var/datum/computer_file/program/interim_program_actor/program = allocate(/datum/computer_file/program/interim_program_actor)
	TEST_ASSERT(computer.hard_drive.store_file(program), "the actual drive stores its autorun executable")
	TEST_ASSERT(computer.hard_drive.check_functionality(), "the real drive is enabled and intact")
	TEST_ASSERT_EQUAL(computer.hard_drive.holder2(), computer, "the real hardware installer associates the drive with its computer")
	TEST_ASSERT_EQUAL(computer.hard_drive.find_file_by_name(program.filename), program, "the actual drive lookup retrieves the stored executable")
	TEST_ASSERT(program.is_supported_by_hardware(computer.hardware_flag), "the actual executable supports this computer hardware")
	var/datum/computer_file/data/autorun = allocate(/datum/computer_file/data)
	autorun.filename = "autorun"
	autorun.stored_data = program.filename
	TEST_ASSERT(computer.hard_drive.store_file(autorun), "the actual drive stores the autorun instruction")
	computer.enable_computer(actor)
	TEST_ASSERT(computer.enabled, "the real startup enables the computer")
	TEST_ASSERT_EQUAL(program.run_actor_ref, REF(actor), "the actual autorun path forwards the startup actor")
	TEST_ASSERT_EQUAL(program.program_state, PROGRAM_STATE_ACTIVE, "the actual autorun activates the authorized executable")
	TEST_ASSERT_EQUAL(computer.active_program(), program, "the actual autorun installs its foreground executable")
	TEST_ASSERT_EQUAL(computer.window_actor_ref, REF(actor), "startup requests its window for the same actual actor")

/datum/unit_test/interim_computer_module_quit_actor/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT(interim_computer_actor_card(actor, T), "the real quitting actor is authorized")
	var/obj/item/modular_computer/interim_program_actor/computer = allocate(/obj/item/modular_computer/interim_program_actor, T)
	var/datum/computer_file/program/interim_program_actor/program = allocate(/datum/computer_file/program/interim_program_actor)
	TEST_ASSERT(computer.hard_drive.store_file(program), "the real drive stores the executable")
	TEST_ASSERT(computer.hard_drive.check_functionality(), "the real drive is enabled and intact")
	TEST_ASSERT_EQUAL(computer.hard_drive.holder2(), computer, "the real hardware installer associates the drive with its computer")
	TEST_ASSERT_EQUAL(computer.hard_drive.find_file_by_name(program.filename), program, "the actual drive lookup retrieves the stored executable")
	TEST_ASSERT(program.is_supported_by_hardware(computer.hardware_flag), "the actual executable supports this computer hardware")
	computer.run_program(program.filename, actor)
	TEST_ASSERT_EQUAL(computer.active_program(), program, "the actual executable is running before module quit")
	var/datum/tgui_module/module = allocate(/datum/tgui_module, computer)
	TEST_ASSERT(test_op_committed(op_ui_act(actor, module, "PC_exit")), "the actual module header accepts quit")
	TEST_ASSERT_EQUAL(program.program_state, PROGRAM_STATE_KILLED, "the module header kills the actual foreground executable")
	TEST_ASSERT_NULL(computer.active_program(), "the module header clears the actual foreground relation")
	test_time(0.2 SECONDS)
	TEST_ASSERT_EQUAL(computer.window_requests, 1, "the real module quit schedules one main-menu request")
	TEST_ASSERT_EQUAL(computer.window_actor_ref, REF(actor), "the actual module quit retains its explicit actor")

/datum/unit_test/interim_hard_drive_file_list/Run()
	var/obj/item/computer_hardware/hard_drive/drive = allocate(/obj/item/computer_hardware/hard_drive)
	TEST_ASSERT(islist(drive.stored_files), "default programs occupy an actual owned list")
	TEST_ASSERT_EQUAL(length(drive.stored_files), 3, "all three default programs survive drive initialization")
	TEST_ASSERT_NOTNULL(drive.find_file_by_name("compconfig"), "the first default program remains retrievable")
	TEST_ASSERT_NOTNULL(drive.find_file_by_name("ntndownloader"), "the second default program remains retrievable")
	TEST_ASSERT_NOTNULL(drive.find_file_by_name("filemanager"), "the third default program remains retrievable")
	var/datum/computer_file/data/first = allocate(/datum/computer_file/data)
	first.filename = "interim_first"
	var/datum/computer_file/data/second = allocate(/datum/computer_file/data)
	second.filename = "interim_second"
	TEST_ASSERT(drive.store_file(first), "the actual drive accepts the first additional file")
	TEST_ASSERT(drive.store_file(second), "the actual drive accepts the second additional file")
	TEST_ASSERT_EQUAL(length(drive.stored_files), 5, "storing another file preserves all earlier files")
	TEST_ASSERT_EQUAL(drive.find_file_by_name(first.filename), first, "the first additional file remains retrievable")
	TEST_ASSERT_EQUAL(drive.find_file_by_name(second.filename), second, "the second additional file remains retrievable")
	var/expected_capacity = 0
	for(var/datum/computer_file/file in drive.stored_files)
		expected_capacity += file.size
	TEST_ASSERT_EQUAL(drive.used_capacity, expected_capacity, "capacity accounts for every retained file")
	var/obj/item/computer_hardware/hard_drive/destination = allocate(/obj/item/computer_hardware/hard_drive)
	var/list/defaults = destination.stored_files.Copy()
	for(var/datum/computer_file/file in defaults)
		TEST_ASSERT(destination.remove_file(file), "the real removal API empties the destination drive")
		own(file)
	TEST_ASSERT_NULL(destination.stored_files, "removing the last file restores the lazy list to null")
	TEST_ASSERT(drive.remove_file(first), "the real removal API releases the file and updates donor capacity")
	TEST_ASSERT_NULL(owner_of(first), "the released file is actually unowned")
	TEST_ASSERT(destination.store_file(first), "the real storage API adopts a file into the emptied drive")
	TEST_ASSERT_EQUAL(destination.find_file_by_name(first.filename), first, "the transferred file is retrievable in its new drive")
	TEST_ASSERT_NULL(drive.find_file_by_name(first.filename), "the transferred file leaves its old drive")
	TEST_ASSERT_EQUAL(owner_of(first), destination, "the transfer updates actual ownership")
	TEST_ASSERT_EQUAL(destination.used_capacity, first.size, "the emptied drive accounts for its adopted file")
	TEST_ASSERT_EQUAL(drive.used_capacity, expected_capacity - first.size, "the donor capacity reflects the transferred file")

/datum/unit_test/interim_hard_drive_direct_transfer/Run()
	var/obj/item/computer_hardware/hard_drive/donor = allocate(/obj/item/computer_hardware/hard_drive)
	var/obj/item/computer_hardware/hard_drive/destination = allocate(/obj/item/computer_hardware/hard_drive)
	var/list/donor_defaults = donor.stored_files.Copy()
	var/list/destination_defaults = destination.stored_files.Copy()
	var/donor_default_capacity = donor.used_capacity
	var/destination_default_capacity = destination.used_capacity
	var/datum/computer_file/data/transferred = allocate(/datum/computer_file/data)
	transferred.filename = "interim_direct_transfer"
	transferred.size = 7
	TEST_ASSERT(donor.store_file(transferred), "the real donor stores a seven-unit file")
	TEST_ASSERT_EQUAL(donor.used_capacity, donor_default_capacity + 7, "donor capacity includes its new file")
	TEST_ASSERT(destination.store_file(transferred), "the real storage API directly moves an already owned file")
	TEST_ASSERT_EQUAL(owner_of(transferred), destination, "the exact file becomes owned by its destination")
	TEST_ASSERT_EQUAL(transferred.holder(), destination, "the file holder relation resolves its new drive")
	TEST_ASSERT_EQUAL(destination.find_file_by_name(transferred.filename), transferred, "destination lookup returns the exact transferred object")
	TEST_ASSERT_NULL(donor.find_file_by_name(transferred.filename), "donor lookup no longer returns the transferred file")
	TEST_ASSERT_EQUAL(donor.used_capacity, donor_default_capacity, "direct transfer releases exactly seven units of donor capacity")
	TEST_ASSERT_EQUAL(destination.used_capacity, destination_default_capacity + 7, "destination gains exactly seven units of capacity")
	TEST_ASSERT_EQUAL(length(donor.stored_files), 3, "the donor keeps all three default files")
	TEST_ASSERT_EQUAL(length(destination.stored_files), 4, "the destination keeps its defaults alongside the transferred file")
	for(var/datum/computer_file/file in donor_defaults)
		TEST_ASSERT_EQUAL(donor.find_file_by_name(file.filename), file, "the donor keeps the exact default file identity")
		TEST_ASSERT_EQUAL(owner_of(file), donor, "donor defaults keep their actual owner")
	for(var/datum/computer_file/file in destination_defaults)
		TEST_ASSERT_EQUAL(destination.find_file_by_name(file.filename), file, "the destination keeps the exact default file identity")
		TEST_ASSERT_EQUAL(owner_of(file), destination, "destination defaults keep their actual owner")
	// A failed transfer must leave the file and both capacity counters intact.
	donor.max_capacity = donor.used_capacity
	TEST_ASSERT(!donor.store_file(transferred), "a drive without spare capacity rejects the actual transfer")
	TEST_ASSERT_EQUAL(owner_of(transferred), destination, "the refused transfer retains destination ownership")
	TEST_ASSERT_EQUAL(destination.find_file_by_name(transferred.filename), transferred, "refusal retains the exact file in its current drive")
	TEST_ASSERT_EQUAL(donor.used_capacity, donor_default_capacity, "refusal leaves donor capacity unchanged")
	TEST_ASSERT_EQUAL(destination.used_capacity, destination_default_capacity + 7, "refusal leaves destination capacity unchanged")


/// Actual stored malware retires its own drive without losing the remaining target context.
/datum/unit_test/interim_revelation_owned_hardware/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/item/modular_computer/laptop/computer = allocate(/obj/item/modular_computer/laptop, T)
	var/obj/item/modular_computer/laptop/control = allocate(/obj/item/modular_computer/laptop, T)
	var/obj/item/computer_hardware/hard_drive/drive = allocate(/obj/item/computer_hardware/hard_drive, computer)
	var/obj/item/computer_hardware/hard_drive/control_drive = allocate(/obj/item/computer_hardware/hard_drive, control)
	computer.install_hardware(drive)
	control.install_hardware(control_drive)
	TEST_ASSERT_EQUAL(computer.hard_drive, drive, "real hardware installation binds the original victim drive")
	TEST_ASSERT_EQUAL(owner_of(drive), computer, "the victim computer owns its original installed drive")
	TEST_ASSERT_EQUAL(control.hard_drive, control_drive, "the independent computer owns its original control drive")
	TEST_ASSERT_NULL(computer.battery_module, "this real laptop has no optional battery module")
	TEST_ASSERT_NULL(computer.tesla_link, "this real laptop has no optional tesla module")
	var/datum/computer_file/program/revelation/program = allocate(/datum/computer_file/program/revelation, computer)
	TEST_ASSERT(drive.store_file(program), "the real hard-drive API stores its actual malware executable")
	TEST_ASSERT_EQUAL(owner_of(program), drive, "the stored executable is owned by the drive it will retire")
	TEST_ASSERT_EQUAL(program.computer(), computer, "the actual executable retains its constructor target")
	computer.set_enabled(TRUE)
	TEST_ASSERT(computer.enabled, "the victim computer is enabled before the actual activation")
	program.activate()
	TEST_ASSERT(QDELETED(drive), "actual activation deletes the exact original victim drive")
	TEST_ASSERT(QDELETED(program), "the drive retires its exact originally stored executable")
	TEST_ASSERT_NULL(computer.hard_drive, "the native owned slot clears after drive retirement")
	TEST_ASSERT(!computer.enabled, "the actual malware disables its victim computer")
	TEST_ASSERT_EQUAL(computer.last_power_usage, 0, "the actual malware leaves no power usage")
	TEST_ASSERT(!QDELETED(computer), "the victim chassis survives its own hardware retirement")
	TEST_ASSERT(!QDELETED(control_drive), "unrelated original hardware survives the actual activation")
	TEST_ASSERT_EQUAL(control.hard_drive, control_drive, "the independent computer keeps its exact original drive")
	TEST_ASSERT_EQUAL(owner_of(control_drive), control, "unrelated drive ownership remains unchanged")
	own_turf_contents(T)
