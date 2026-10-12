// New metadata proof only after stat accessor migration; real composed condition behavior unchanged.
/datum/unit_test/dq_machine_condition_native_reads/Run()
	var/obj/machinery/firealarm/F = allocate(/obj/machinery/firealarm, test_floor())
	for(var/proc_name in list("power_lost", "broken_now", "under_maintenance", "switched_off", "operable"))
		var/stat_id
		switch(proc_name)
			if("power_lost") stat_id = STAT_HAS_POWER
			if("broken_now") stat_id = STAT_INTACT
			if("under_maintenance") stat_id = STAT_IN_MAINTENANCE
			if("switched_off") stat_id = STAT_SWITCHED_ON
			if("operable") stat_id = STAT_OPERABLE
		var/datum/stat_def/D = stat_def_of(stat_id)
		var/list/reads = change_read_keys(F, proc_name)
		TEST_ASSERT(D.stat_key in reads, "[proc_name] reads the actual composed stat's published key; actual=[json_encode(reads)]")
		TEST_ASSERT(!(MACHINE_KEY_STAT in reads), "[proc_name] no longer substitutes a synthetic stat var for real condition source")
	F.atom_fix()
	TEST_ASSERT(!F.broken_now(), "real repair restores intact")
	F.atom_break()
	TEST_ASSERT(F.broken_now(), "real break contributes broken state")
	F.set_maintenance(TRUE)
	TEST_ASSERT(F.under_maintenance(), "real hatch condition holds maintenance")
	F.set_maintenance(FALSE)
	TEST_ASSERT(!F.under_maintenance(), "real hatch release clears maintenance")

// The proc condition, not a numeric stat argument, exercises generated stat reads.
/obj/machinery/firealarm/dq_condition_edge_probe
	abstract_type = /obj/machinery/firealarm/dq_condition_edge_probe
	var/entered = 0
	var/exited = 0

CAPABILITIES(/obj/machinery/firealarm/dq_condition_edge_probe)
	on_change(cond_not(STAT_INTACT), ENTER, then(PROC_REF(broken_entered)))
	on_change(cond_not(STAT_INTACT), EXIT, then(PROC_REF(broken_exited)))

/obj/machinery/firealarm/dq_condition_edge_probe/proc/broken_entered(datum/act/A)
	entered++

/obj/machinery/firealarm/dq_condition_edge_probe/proc/broken_exited(datum/act/A)
	exited++

/datum/unit_test/dq_machine_condition_native_edges/Run()
	var/obj/machinery/firealarm/dq_condition_edge_probe/F = allocate(/obj/machinery/firealarm/dq_condition_edge_probe, test_floor())
	F.atom_fix()
	act_drain_point()
	var/before_enter = F.entered
	var/before_exit = F.exited
	F.atom_break()
	TEST_ASSERT(F.broken_now(), "Actual damage changes the composed stat condition")
	TEST_ASSERT_EQUAL(F.entered, before_enter, "Delivery waits for the reaction drain")
	act_drain_point()
	TEST_ASSERT_EQUAL(F.entered, before_enter + 1, "Published stat key triggers the proc's ENTER hook")
	TEST_ASSERT_EQUAL(F.exited, before_exit, "Break does not trigger EXIT")
	F.atom_break()
	act_drain_point()
	TEST_ASSERT_EQUAL(F.entered, before_enter + 1, "Unchanged broken condition has no extra edge")
	F.atom_fix()
	act_drain_point()
	TEST_ASSERT(!F.broken_now(), "Real repair restores the composed stat condition")
	TEST_ASSERT_EQUAL(F.exited, before_exit + 1, "Published stat key triggers the proc's EXIT hook")
	TEST_ASSERT_EQUAL(F.entered, before_enter + 1, "Repair does not trigger another ENTER")
