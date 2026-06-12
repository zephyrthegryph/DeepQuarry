// Reinforcement siege — "going loud" turns heat into sustained pressure.
//
// Separate from the ambient event roller (pebbles/tremor/gas leak): once a
// layer's heat (danger) crosses QUARRY_REINFORCE_MIN_DANGER, it lays siege.
// Waves of depth-appropriate mobs spawn just off-screen and beeline the nearest
// player, on a cadence and in sizes that tighten as heat climbs toward 100. Each
// 30s danger tick a hot layer schedules that window's worth of waves, spread
// across the tick and sized by heat — so the pressure feels continuous at high
// heat without a persistent loop that could race a layer unload/reload. Waves
// stop once heat bleeds below the threshold, the layer empties, or it unloads.
// Heat cools when the layer goes quiet (see tick_layer_danger), so breaking
// contact ends the swarm — the core go-loud / go-quiet loop the mode is built on.

/// 0 at MIN heat, 1 at 100 heat. Drives both wave cadence and wave size.
/datum/controller/subsystem/quarry/proc/siege_intensity(danger)
	return clamp((danger - QUARRY_REINFORCE_MIN_DANGER) / (100 - QUARRY_REINFORCE_MIN_DANGER), 0, 1)

/// Heat-scaled wave spacing in deciseconds: SLOW at MIN heat, FAST at 100.
/datum/controller/subsystem/quarry/proc/siege_interval(danger)
	var/t = siege_intensity(danger)
	return max(round(QUARRY_REINFORCE_INTERVAL_SLOW + (QUARRY_REINFORCE_INTERVAL_FAST - QUARRY_REINFORCE_INTERVAL_SLOW) * t), QUARRY_REINFORCE_INTERVAL_FAST)

/// Called from tick_layer_danger for a hot layer, once per 30s tick. Schedules
/// this window's worth of waves spread across the tick, sized by heat — so the
/// cadence tightens as heat climbs without a persistent self-rescheduling loop
/// (which would race a layer unload/reload). Each scheduled spawn re-checks the
/// layer, so a layer that cools or empties mid-window simply stops spawning.
/datum/controller/subsystem/quarry/proc/schedule_siege_waves(datum/quarry_layer/L)
	if(!L || L.danger < QUARRY_REINFORCE_MIN_DANGER)
		return
	if(!L.loaded || L.unloading || is_layer_empty(L.z))
		return
	var/interval = siege_interval(L.danger)
	// How many waves fit in one SS tick at the current cadence (at least one).
	var/waves = clamp(round(wait / interval), 1, round(wait / QUARRY_REINFORCE_INTERVAL_FAST))
	for(var/i in 0 to waves - 1)
		addtimer(CALLBACK(src, PROC_REF(spawn_reinforcement_wave_for_depth), L.depth), round(i * wait / waves))

/// Timer entry: re-fetch the layer by depth (stable across reload) and spawn one
/// wave if it's still loaded, occupied, and hot.
/datum/controller/subsystem/quarry/proc/spawn_reinforcement_wave_for_depth(depth)
	var/datum/quarry_layer/L = get_layer(depth)
	if(!L || !L.loaded || L.unloading || L.danger < QUARRY_REINFORCE_MIN_DANGER)
		return
	if(is_layer_empty(L.z))
		return
	spawn_reinforcement_wave(L)

/// Living, cliented players with a turf on this layer — eaten/contained players
/// included via get_turf (they still anchor a wave). Observers are excluded so a
/// wave never tries to swarm an incorporeal ghost.
/datum/controller/subsystem/quarry/proc/players_on_layer(z)
	var/list/out = list()
	for(var/mob/living/M in GLOB.mob_list)
		if(!M.client)
			continue
		var/turf/MT = get_turf(M)
		if(MT && MT.z == z)
			out += M
	return out

/// Count living reinforcement-wave mobs on a layer (the siege cap denominator).
/// Only siege spawns count — ambient gen-time fauna don't, so a populated layer
/// still gets its swarm.
/datum/controller/subsystem/quarry/proc/count_layer_reinforcements(z)
	var/count = 0
	for(var/mob/living/simple_mob/M in GLOB.living_mob_list)
		if(!M.siege_reinforcement || M.stat == DEAD)
			continue
		var/turf/MT = get_turf(M)
		if(MT && MT.z == z)
			count++
	return count

/// One converging wave: pick a player, a single depth-appropriate species, and a
/// cluster of free tiles ~QUARRY_REINFORCE_RING away (off-screen), then give every
/// mob that player as a target so they swarm in rather than wander.
/datum/controller/subsystem/quarry/proc/spawn_reinforcement_wave(datum/quarry_layer/L)
	// Fairness + perf cap: let the player thin an existing swarm before piling on.
	if(count_layer_reinforcements(L.z) >= QUARRY_REINFORCE_MAX_ALIVE)
		return
	var/list/players = players_on_layer(L.z)
	if(!length(players))
		return
	var/mob/target_player = pick(players)
	// Aggregate the layer's feature mob table once, then reuse it every wave.
	if(!L.reinforce_mob_table)
		var/list/aggregated = _quarry_aggregate_features(L.feature_types, L)
		L.reinforce_mob_table = aggregated["mob_table"]
	var/list/mob_table = L.reinforce_mob_table
	if(!length(mob_table))
		return
	var/mob_type = pickweight(mob_table)
	if(!mob_type)
		return
	var/turf/seed = pick_reinforcement_tile(L, target_player)
	if(!seed)
		return
	var/t = siege_intensity(L.danger)
	var/wave = max(QUARRY_REINFORCE_WAVE_MIN, round(QUARRY_REINFORCE_WAVE_MIN + (QUARRY_REINFORCE_WAVE_MAX - QUARRY_REINFORCE_WAVE_MIN) * t))
	// Distant skittering — the swarm is heard closing in before it's seen.
	playsound(seed, 'sound/effects/rustle4.ogg', 70, 1)
	// Single species per wave (same faction => no infighting), clustered on the
	// seed + its free neighbours, every one targeting the chosen player.
	var/list/tiles = list(seed)
	for(var/dir in GLOB.alldirs)
		if(length(tiles) >= wave)
			break
		var/turf/N = get_step(seed, dir)
		if(istype(N, /turf/simulated/floor) && !N.density && !length(N.contents))
			tiles += N
	var/spawned = 0
	for(var/turf/T as anything in tiles)
		if(spawned >= wave)
			break
		var/spawned_mob = new mob_type(T)
		if(istype(spawned_mob, /mob/living/simple_mob))
			var/mob/living/simple_mob/SM = spawned_mob
			SM.quarry_fauna = TRUE
			SM.siege_reinforcement = TRUE
			SM.ai_brain?.give_target(target_player, TRUE)
		spawned++

/// A free floor tile ~QUARRY_REINFORCE_RING tiles from the player (just beyond the
/// default view, so the wave appears off-screen), not in the bay or a powered safe
/// room. Tries a handful of random bearings; null if the player is too boxed in.
/datum/controller/subsystem/quarry/proc/pick_reinforcement_tile(datum/quarry_layer/L, mob/player)
	var/turf/origin = get_turf(player)
	if(!origin)
		return null
	var/list/bay = elevator?.bay_at(L.depth)
	for(var/i in 1 to 12)
		var/angle = rand(1, 360)
		var/nx = clamp(origin.x + round(cos(angle) * QUARRY_REINFORCE_RING), 2, QUARRY_LAYER_SIZE - 1)
		var/ny = clamp(origin.y + round(sin(angle) * QUARRY_REINFORCE_RING), 2, QUARRY_LAYER_SIZE - 1)
		var/turf/T = locate(nx, ny, L.z)
		if(!istype(T, /turf/simulated/floor) || T.density || length(T.contents))
			continue
		if(bay && (T in bay))
			continue
		if(_quarry_tile_is_safe(T))
			continue
		// Re-check distance: clamping near a map edge can pull the tile back into view.
		if(get_dist(T, player) < QUARRY_REINFORCE_RING - 2)
			continue
		return T
	return null
