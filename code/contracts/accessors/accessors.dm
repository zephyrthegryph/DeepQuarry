// System accessors (doc/rewrite/final_api.html, section 7 "The graph contract"; section 22). A system's state is private;
// content reads it through the reactive accessor its api.dm declares with SYSTEM_ACCESSOR(system, name, nameof(var)), whose
// declaration sits here so every layer can see it and none names the system. The generator (E5) emits the accessor proc
// into code/engine/_generated/ and teaches generated reads to follow it to the tracked var: a write to the var marks every
// stat that read the accessor for the next drain point (a marked, not an inline, recompute).
//
// Declarations only: a proc never lives in the contracts layer. `analyze gen system_accessors` writes the accessor proc to
// code/engine/_generated/system_accessors.dm (the var must exist on the system: the keys lint checks it).

/// Whether the night-shift system is in night mode (16.11). Read by an APC's wants_night_lights().
SYSTEM_ACCESSOR(nightshift, night_shift_active, nameof(nightshift_active))

/// Read-only scalar diagnostics; private queues and mutable system lists stay behind their owner APIs.
SYSTEM_ACCESSOR(air, air_profile_cost_highpressure, nameof(cost_highpressure))
SYSTEM_ACCESSOR(air, air_profile_cost_superconductivity, nameof(cost_superconductivity))
SYSTEM_ACCESSOR(air, air_profile_cost_pipenets, nameof(cost_pipenets))
SYSTEM_ACCESSOR(air, air_profile_cost_pipe_commit, nameof(cost_pipe_commit))
SYSTEM_ACCESSOR(air, air_profile_cost_pipe_devices, nameof(cost_pipe_devices))
SYSTEM_ACCESSOR(air, air_profile_cost_rebuilds, nameof(cost_rebuilds))
SYSTEM_ACCESSOR(air, air_profile_cost_turfs, nameof(cost_turfs))
SYSTEM_ACCESSOR(air, air_profile_cost_gas_events, nameof(cost_gas_events))
SYSTEM_ACCESSOR(air, air_profile_gas_events_last, nameof(gas_events_last))
SYSTEM_ACCESSOR(air, air_profile_gas_reactions_last, nameof(gas_reactions_last))
SYSTEM_ACCESSOR(air, air_profile_gas_visuals_last, nameof(gas_visuals_last))
SYSTEM_ACCESSOR(air, air_profile_gas_pressure_last, nameof(gas_pressure_last))
SYSTEM_ACCESSOR(air, air_profile_rust_pipe_device_count, nameof(rust_pipe_device_count))
SYSTEM_ACCESSOR(machines, machine_profile_cost_machinery, nameof(cost_machinery))
SYSTEM_ACCESSOR(machines, machine_profile_cost_powernets, nameof(cost_powernets))
SYSTEM_ACCESSOR(machines, machine_profile_last_cost_machinery, nameof(last_cost_machinery))
SYSTEM_ACCESSOR(machines, machine_profile_last_cost_powernets, nameof(last_cost_powernets))
SYSTEM_ACCESSOR(machines, machine_profile_last_pump_commit_ms, nameof(last_pump_commit_ms))
SYSTEM_ACCESSOR(machines, machine_profile_last_pump_commit_wall_ms, nameof(last_pump_commit_wall_ms))
SYSTEM_ACCESSOR(machines, machine_profile_last_pump_commit_suspended_ms, nameof(last_pump_commit_suspended_ms))
SYSTEM_ACCESSOR(machines, machine_profile_last_pump_commit_operations, nameof(last_pump_commit_operations))
SYSTEM_ACCESSOR(machines, machine_profile_last_pump_commit_turfs, nameof(last_pump_commit_turfs))
SYSTEM_ACCESSOR(machines, machine_profile_gas_dirty_last, nameof(gas_dirty_last))
SYSTEM_ACCESSOR(machines, machine_profile_gas_wake_subscribers_last, nameof(gas_wake_subscribers_last))
SYSTEM_ACCESSOR(machines, machine_profile_gas_wake_scan_last_ms, nameof(gas_wake_scan_last_ms))
SYSTEM_ACCESSOR(machines, machine_profile_gas_woken_last, nameof(gas_woken_last))
SYSTEM_ACCESSOR(machines, machine_profile_gas_dead_last, nameof(gas_dead_last))
SYSTEM_ACCESSOR(ticker, round_game_state, nameof(current_state))
SYSTEM_ACCESSOR(supply, supply_money_per_point, nameof(points_per_money))
SYSTEM_ACCESSOR(nerdle, nerdle_round_word, nameof(target_word))
SYSTEM_ACCESSOR(nerdle, nerdle_player_count, nameof(total_players))
