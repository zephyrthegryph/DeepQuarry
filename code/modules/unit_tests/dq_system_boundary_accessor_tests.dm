// Accessors expose real scalar values without handing out private mutable state.
/datum/unit_test/dq_system_boundary_scalar_accessors/Run()
	var/list/reads = list(
		list(SSair, "cost_highpressure", GLOBAL_PROC_REF(air_profile_cost_highpressure)),
		list(SSair, "cost_superconductivity", GLOBAL_PROC_REF(air_profile_cost_superconductivity)),
		list(SSair, "cost_pipenets", GLOBAL_PROC_REF(air_profile_cost_pipenets)),
		list(SSair, "cost_pipe_commit", GLOBAL_PROC_REF(air_profile_cost_pipe_commit)),
		list(SSair, "cost_pipe_devices", GLOBAL_PROC_REF(air_profile_cost_pipe_devices)),
		list(SSair, "cost_rebuilds", GLOBAL_PROC_REF(air_profile_cost_rebuilds)),
		list(SSair, "cost_turfs", GLOBAL_PROC_REF(air_profile_cost_turfs)),
		list(SSair, "cost_gas_events", GLOBAL_PROC_REF(air_profile_cost_gas_events)),
		list(SSair, "gas_events_last", GLOBAL_PROC_REF(air_profile_gas_events_last)),
		list(SSair, "gas_reactions_last", GLOBAL_PROC_REF(air_profile_gas_reactions_last)),
		list(SSair, "gas_visuals_last", GLOBAL_PROC_REF(air_profile_gas_visuals_last)),
		list(SSair, "gas_pressure_last", GLOBAL_PROC_REF(air_profile_gas_pressure_last)),
		list(SSair, "rust_pipe_device_count", GLOBAL_PROC_REF(air_profile_rust_pipe_device_count)),
		list(SSmachines, "cost_machinery", GLOBAL_PROC_REF(machine_profile_cost_machinery)),
		list(SSmachines, "cost_powernets", GLOBAL_PROC_REF(machine_profile_cost_powernets)),
		list(SSmachines, "last_cost_machinery", GLOBAL_PROC_REF(machine_profile_last_cost_machinery)),
		list(SSmachines, "last_cost_powernets", GLOBAL_PROC_REF(machine_profile_last_cost_powernets)),
		list(SSmachines, "last_pump_commit_ms", GLOBAL_PROC_REF(machine_profile_last_pump_commit_ms)),
		list(SSmachines, "last_pump_commit_wall_ms", GLOBAL_PROC_REF(machine_profile_last_pump_commit_wall_ms)),
		list(SSmachines, "last_pump_commit_suspended_ms", GLOBAL_PROC_REF(machine_profile_last_pump_commit_suspended_ms)),
		list(SSmachines, "last_pump_commit_operations", GLOBAL_PROC_REF(machine_profile_last_pump_commit_operations)),
		list(SSmachines, "last_pump_commit_turfs", GLOBAL_PROC_REF(machine_profile_last_pump_commit_turfs)),
		list(SSmachines, "gas_dirty_last", GLOBAL_PROC_REF(machine_profile_gas_dirty_last)),
		list(SSmachines, "gas_wake_subscribers_last", GLOBAL_PROC_REF(machine_profile_gas_wake_subscribers_last)),
		list(SSmachines, "gas_wake_scan_last_ms", GLOBAL_PROC_REF(machine_profile_gas_wake_scan_last_ms)),
		list(SSmachines, "gas_woken_last", GLOBAL_PROC_REF(machine_profile_gas_woken_last)),
		list(SSmachines, "gas_dead_last", GLOBAL_PROC_REF(machine_profile_gas_dead_last))
	)
	var/index = 0
	for(var/list/read as anything in reads)
		var/datum/owner = read[1]
		var/expected = ++index + 0.125
		set_var(owner, read[2], expected)
		var/value = call(read[3])()
		TEST_ASSERT_EQUAL(value, expected, "The generated diagnostic getter returns its owner's exact scalar: [read[2]]")
	set_var(SSticker, "current_state", GAME_STATE_FINISHED)
	TEST_ASSERT_EQUAL(round_game_state(), GAME_STATE_FINISHED, "The state getter reads the actual ticker state")
	set_var(SSnerdle, "target_word", "accessor-probe")
	set_var(SSnerdle, "total_players", 17)
	TEST_ASSERT_EQUAL(nerdle_round_word(), "accessor-probe", "The word getter reads the actual round's word")
	TEST_ASSERT_EQUAL(nerdle_player_count(), 17, "The player getter reads the actual count")
	set_var(SSsupply, "points_per_money", 0.375)
	TEST_ASSERT_EQUAL(supply_money_per_point(), 0.375, "The conversion getter preserves a fractional rate")
	TEST_ASSERT_EQUAL(2.5 * supply_money_per_point(), 0.9375, "The existing report multiplication preserves fractional proceeds without rounding")
