// Per-layer danger system.
//
// Danger is a 0..100 scalar on /datum/quarry_layer that represents how
// agitated the cave has become. It accrues from time loaded, walls
// mined, machinery running, gas vents, and mob kills, and decays
// slowly while the layer has no live players on it. At thresholds the
// danger system triggers escalating effects — currently hostile mob
// waves at critical.
//
// Per-event accrual hooks are called from the same event sources that
// drive goal progress (GetDrilled, pump_reagents, raw_chem_vent,
// /mob/living/death). Time-based accrual + threshold effects run from
// SSquarry.fire() at the SS tick (30s).
//
// Persistence: `danger` and `last_danger_wave` are saved on the layer
// snapshot so unload/restore round-trips the state.

// Thresholds and accrual rates live in quarry_defines.dm so the
// goal-hook procs can reference them at parse time.

// Bump a layer's danger by `amount`, clamped to 0..100. Called from
// event hooks and the tick.
/datum/controller/subsystem/quarry/proc/add_layer_danger(datum/quarry_layer/L, amount)
	if(!L || !isnum(amount))
		return
	L.danger = clamp(L.danger + amount, 0, 100)


// Convenience event hooks — mirror the goal dispatch routing.

/datum/controller/subsystem/quarry/proc/on_layer_wall_mined_for_danger(z)
	var/datum/quarry_layer/L = layer_at_z(z)
	if(L)
		add_layer_danger(L, QUARRY_DANGER_PER_WALL_MINED)

/datum/controller/subsystem/quarry/proc/on_layer_pump_tick_for_danger(z)
	var/datum/quarry_layer/L = layer_at_z(z)
	if(L)
		add_layer_danger(L, QUARRY_DANGER_PER_PUMP_TICK)

/datum/controller/subsystem/quarry/proc/on_layer_gas_vent_for_danger(z)
	var/datum/quarry_layer/L = layer_at_z(z)
	if(L)
		add_layer_danger(L, QUARRY_DANGER_PER_GAS_VENT)

/datum/controller/subsystem/quarry/proc/on_layer_mob_kill_for_danger(z)
	var/datum/quarry_layer/L = layer_at_z(z)
	if(L)
		add_layer_danger(L, QUARRY_DANGER_PER_MOB_KILL)


// Per-SS-tick driver. Walks every loaded layer:
//   - Adds passive danger if at least one live player is on it.
//   - Decays danger if empty.
//   - Fires hostile waves at critical danger.
/datum/controller/subsystem/quarry/proc/tick_layer_danger()
	for(var/key in layers)
		var/datum/quarry_layer/L = layers[key]
		if(!L?.loaded || L.unloading)
			continue
		var/has_players = !is_layer_empty(L.z)
		if(has_players)
			add_layer_danger(L, QUARRY_DANGER_PASSIVE_BASE + QUARRY_DANGER_PASSIVE_PER_DEPTH * L.depth)
		else
			add_layer_danger(L, -QUARRY_DANGER_DECAY)


// (Monster waves at critical danger now live in quarry_events.dm as
// /datum/quarry_event/monster_swarm.)


// Human-readable danger band name for the UI.
/proc/quarry_danger_label(danger)
	if(danger >= QUARRY_DANGER_DANGEROUS)
		return "Critical"
	if(danger >= QUARRY_DANGER_RESTLESS)
		return "Dangerous"
	if(danger >= QUARRY_DANGER_QUIET)
		return "Restless"
	return "Quiet"
