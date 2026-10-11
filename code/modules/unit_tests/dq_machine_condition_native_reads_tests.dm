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
