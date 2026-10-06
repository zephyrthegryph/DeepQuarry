// The machines' maintenance ops (code/game/machinery/machinery_maintenance.dm, the `maintenance` section of CAPABILITIES(/obj/machinery)):
// a screwdriver opens and closes the panel, a crowbar takes the machine apart behind the open panel, a wrench secures or unsecures it with the
// panel shut, a lit welder repairs damage; each only on a type whose maintenance_flags offer it.

/// Every maintenance flag, no waits, and a recorded dismantle.
/obj/machinery/dq_maint_machine
	name = "maintenance machine"
	maintenance_flags = MACHINE_MAINT_PANEL | MACHINE_MAINT_FRAME | MACHINE_MAINT_WRENCH | MACHINE_MAINT_WELDER_REPAIR
	maintenance_wrench_time = 0
	maintenance_weld_time = 0
	use_power = USE_POWER_OFF
	anchored = TRUE
	var/dismantled = 0

/obj/machinery/dq_maint_machine/dismantle()
	dismantled++
	return TRUE

/// Only a panel: the other tools find nothing to do.
/obj/machinery/dq_maint_machine/panel_only
	maintenance_flags = MACHINE_MAINT_PANEL

/datum/unit_test/dq_machine_maintenance

/datum/unit_test/dq_machine_maintenance/proc/tool(path, turf/T)
	var/obj/item/I = allocate(path, T)
	return I

/// The screwdriver opens and closes the panel.
/datum/unit_test/dq_machine_maintenance/panel/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/machinery/dq_maint_machine/machine = allocate(/obj/machinery/dq_maint_machine, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/tool/screwdriver/screwdriver = tool(/obj/item/tool/screwdriver, T)
	TEST_ASSERT(H.put_in_active_hand(screwdriver), "the screwdriver is held")
	test_click(H, machine, screwdriver)
	test_time(1 SECOND)
	TEST_ASSERT(machine.panel_open, "the screwdriver opened the panel")
	test_click(H, machine, screwdriver)
	test_time(1 SECOND)
	TEST_ASSERT(!machine.panel_open, "and closed it again")
	test_driver_end()

/// The crowbar takes the machine apart only behind the open panel.
/datum/unit_test/dq_machine_maintenance/deconstruct/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/machinery/dq_maint_machine/machine = allocate(/obj/machinery/dq_maint_machine, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/tool/crowbar/crowbar = tool(/obj/item/tool/crowbar, T)
	TEST_ASSERT(H.put_in_active_hand(crowbar), "the crowbar is held")
	test_click(H, machine, crowbar)
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(machine.dismantled, 0, "a closed panel keeps the frame whole")
	machine.set_panel_open(TRUE)
	test_click(H, machine, crowbar)
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(machine.dismantled, 1, "behind the open panel it comes apart")
	test_driver_end()

/// The wrench unsecures and secures with the panel shut; an open panel refuses it.
/datum/unit_test/dq_machine_maintenance/anchor/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/machinery/dq_maint_machine/machine = allocate(/obj/machinery/dq_maint_machine, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/tool/wrench/wrench = tool(/obj/item/tool/wrench, T)
	TEST_ASSERT(H.put_in_active_hand(wrench), "the wrench is held")
	test_click(H, machine, wrench)
	test_time(1 SECOND)
	TEST_ASSERT(!machine.anchored, "unsecured")
	machine.set_panel_open(TRUE)
	test_click(H, machine, wrench)
	test_time(1 SECOND)
	TEST_ASSERT(!machine.anchored, "an open panel keeps it loose")
	machine.set_panel_open(FALSE)
	test_click(H, machine, wrench)
	test_time(1 SECOND)
	TEST_ASSERT(machine.anchored, "secured again")
	test_driver_end()

/// A lit welder repairs a damaged machine.
/datum/unit_test/dq_machine_maintenance/repair/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/machinery/dq_maint_machine/machine = allocate(/obj/machinery/dq_maint_machine, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/weldingtool/welder = tool(/obj/item/weldingtool, T)
	TEST_ASSERT(H.put_in_active_hand(welder), "the welder is held")
	welder.set_welding(TRUE)
	machine.take_damage(machine.max_integrity / 2, BRUTE, MELEE, FALSE)
	TEST_ASSERT(machine.get_integrity() < machine.max_integrity, "the machine took damage")
	test_click(H, machine, welder)
	test_time(5 SECONDS)
	TEST_ASSERT_EQUAL(machine.get_integrity(), machine.max_integrity, "fully repaired")
	test_driver_end()

/// Each op follows its flag: a panel-only machine opens its panel, but no crowbar takes it apart and no wrench unsecures it.
/datum/unit_test/dq_machine_maintenance/flags/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/machinery/dq_maint_machine/panel_only/machine = allocate(/obj/machinery/dq_maint_machine/panel_only, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/tool/screwdriver/screwdriver = tool(/obj/item/tool/screwdriver, T)
	var/obj/item/tool/crowbar/crowbar = tool(/obj/item/tool/crowbar, T)
	var/obj/item/tool/wrench/wrench = tool(/obj/item/tool/wrench, T)
	TEST_ASSERT(H.put_in_active_hand(screwdriver), "the screwdriver is held")
	test_click(H, machine, screwdriver)
	test_time(1 SECOND)
	TEST_ASSERT(machine.panel_open, "the panel flag offers the panel")
	H.drop_item()
	TEST_ASSERT(H.put_in_active_hand(crowbar), "the crowbar is held")
	test_click(H, machine, crowbar)
	test_time(1 SECOND)
	TEST_ASSERT_EQUAL(machine.dismantled, 0, "no frame flag: the crowbar takes nothing apart")
	H.drop_item()
	machine.set_panel_open(FALSE)
	TEST_ASSERT(H.put_in_active_hand(wrench), "the wrench is held")
	test_click(H, machine, wrench)
	test_time(1 SECOND)
	TEST_ASSERT(machine.anchored, "no wrench flag: it stays secured")
	test_driver_end()
