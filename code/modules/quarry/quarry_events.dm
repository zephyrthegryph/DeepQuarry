// Runtime cave events.
//
// Distinct from /datum/quarry_feature: features are static layer
// content rolled at generation time (ore veins, pools, mob nests).
// Events are dynamic happenings during play (cave-ins, swarms, gas
// leaks) that fire on the SS tick with probability scaling from the
// layer's danger level.
//
// Authoring a new event = subtype /datum/quarry_event, set the
// eligibility window vars, override fire(L). No registration needed
// beyond defining the subtype; SSquarry discovers them at init via
// subtypesof.

#define QUARRY_EVENT_BASE_CHANCE 0.6  // multiplier on (danger/100) per SS tick
#define QUARRY_EVENT_DEFAULT_COOLDOWN (90 SECONDS)


/datum/quarry_event
	/// Display name for logs/debug.
	var/name = "Cave Event"
	/// Selection weight when SSquarry picks an event for the layer.
	/// Higher = more common when eligible.
	var/weight = 10
	/// Danger band where this event is eligible. Inclusive on min,
	/// exclusive on max. Set to 0 / 100 for no clamp.
	var/min_danger = 0
	var/max_danger = 100
	/// Minimum world.time delay between two of this event on a single
	/// layer. Per-event so heavy events can throttle without blocking
	/// the rate of lighter events.
	var/cooldown = QUARRY_EVENT_DEFAULT_COOLDOWN


/// Override per subtype to make the event do its thing on layer `L`.
/// Default no-op so a half-authored subtype doesn't crash.
/datum/quarry_event/proc/fire(datum/quarry_layer/L)
	return


/// Helper: pick a random floor turf on the layer, optionally
/// excluding the elevator bay so events don't trash the safe room.
/// Returns null if no eligible tile exists.
/datum/quarry_event/proc/pick_layer_floor(datum/quarry_layer/L, exclude_bay = TRUE)
	if(!L?.loaded)
		return null
	var/list/bay = exclude_bay ? SSquarry.elevator?.bay_at(L.depth) : null
	var/list/floors = list()
	for(var/turf/simulated/floor/T in block(locate(1, 1, L.z), locate(QUARRY_LAYER_SIZE, QUARRY_LAYER_SIZE, L.z)))
		if(bay && (T in bay))
			continue
		// Player-built safe rooms (with powered APC) are spawn-safe.
		if(_quarry_tile_is_safe(T))
			continue
		floors += T
	if(!length(floors))
		return null
	return pick(floors)


/// Helper: pick a random floor turf on the layer that's at least
/// `min_dist` tiles away from every player on the layer. Returns
/// null if no eligible tile exists. Used by spawn-far-from-player
/// events (stalker, roaming pack origin tile) so they don't appear
/// on top of someone.
/datum/quarry_event/proc/pick_far_floor(datum/quarry_layer/L, min_dist = 12)
	if(!L?.loaded)
		return null
	var/list/players = list()
	for(var/mob/M in GLOB.mob_list)
		if(M.z == L.z && M.client)
			players += M
	if(!length(players))
		// No players means no anchor for "far"; fall back to any floor.
		return pick_layer_floor(L)
	var/list/bay = SSquarry.elevator?.bay_at(L.depth)
	var/list/eligible = list()
	for(var/turf/simulated/floor/T in block(locate(1, 1, L.z), locate(QUARRY_LAYER_SIZE, QUARRY_LAYER_SIZE, L.z)))
		if(bay && (T in bay))
			continue
		if(length(T.contents))
			continue
		// Player-built safe rooms (with powered APC) are spawn-safe.
		if(_quarry_tile_is_safe(T))
			continue
		var/too_close = FALSE
		for(var/mob/M as anything in players)
			if(get_dist(T, M) < min_dist)
				too_close = TRUE
				break
		if(too_close)
			continue
		eligible += T
	if(!length(eligible))
		return null
	return pick(eligible)


// === EVENT ROSTER =====================================================
//
// Each subtype declares its eligibility window and overrides fire().
// All events live on the layer's z; nothing spills onto other layers.

// --- Loose pebbles: cheap flavor. Always eligible. -------------------
/datum/quarry_event/pebbles
	name = "Loose Pebbles"
	weight = 30
	cooldown = 60 SECONDS

/datum/quarry_event/pebbles/fire(datum/quarry_layer/L)
	var/turf/T = pick_layer_floor(L)
	if(T)
		playsound(T, 'sound/effects/rustle1.ogg', 35, 1)


// --- Tremor: heavier vibration, foreshadows worse things. -----------
/datum/quarry_event/tremor
	name = "Tremor"
	weight = 20
	min_danger = QUARRY_DANGER_QUIET

/datum/quarry_event/tremor/fire(datum/quarry_layer/L)
	// Camera shake + distant rumble is the whole tell. No text.
	for(var/mob/M in GLOB.mob_list)
		if(M.z != L.z)
			continue
		if(M.client)
			shake_camera(M, 12, 1)
		playsound(M, 'sound/effects/explosionfar.ogg', 35, 1)


// --- Gas leak: random pool/vent puffs gas into its surroundings. -----
/datum/quarry_event/gas_leak
	name = "Gas Leak"
	weight = 12
	min_danger = QUARRY_DANGER_RESTLESS

/datum/quarry_event/gas_leak/fire(datum/quarry_layer/L)
	// Find a pool turf and amplify its existing gas signature. For
	// generic pools we just push phoron into adjacent air.
	var/list/pools = list()
	for(var/turf/simulated/floor/gas_crack/c in block(locate(1, 1, L.z), locate(QUARRY_LAYER_SIZE, QUARRY_LAYER_SIZE, L.z)))
		pools += c
	if(!length(pools))
		return
	var/turf/source = pick(pools)
	// Pump-volume hiss carries far enough to be heard across the cave;
	// gas itself is the persistent tell.
	playsound(source, 'sound/effects/spray.ogg', 75, 1)
	var/datum/gas_mixture/leak = new
	// Generic dirty leak — small amount of phoron mixed with N2.
	leak.adjust_gas_temp(GAS_PHORON, 3, T20C + 60)
	leak.adjust_gas_temp(GAS_N2, 5, T20C + 60)
	source.assume_air(leak)


// --- Cave-in: reseals 1-3 connected floor tiles back into walls. ----
/datum/quarry_event/cave_in
	name = "Cave-In"
	weight = 8
	min_danger = QUARRY_DANGER_DANGEROUS

/datum/quarry_event/cave_in/fire(datum/quarry_layer/L)
	// Pick a mineable floor tile, then convert it + 1-2 adjacent
	// floors back to walls via make_wall. Tiles must be /turf/simulated
	// /mineral subtypes (the quarry's mineable rock) so make_wall is
	// available.
	var/turf/simulated/mineral/seed = null
	var/list/bay = SSquarry.elevator?.bay_at(L.depth)
	var/tries = 20
	while(tries-- && !seed)
		var/turf/simulated/mineral/T = locate(rand(2, QUARRY_LAYER_SIZE-1), rand(2, QUARRY_LAYER_SIZE-1), L.z)
		if(!istype(T))
			continue
		if(T.density)
			continue
		if(bay && (T in bay))
			continue
		if(length(T.contents))  // don't seal a tile someone is standing on
			continue
		seed = T
	if(!seed)
		return
	// Loud explosion sound + the new walls themselves are the tell.
	// Players who don't see the sealed tiles will hear the crack.
	playsound(seed, 'sound/effects/explosionfar.ogg', 100, 1, 4)
	SSquarry.emit_noise(seed, QUARRY_NOISE_CAVEIN, seed)
	seed.make_wall()
	var/extra = rand(0, 2)
	for(var/i in 1 to extra)
		for(var/dir in GLOB.cardinal)
			var/turf/simulated/mineral/N = get_step(seed, dir)
			if(!istype(N) || N.density)
				continue
			if(bay && (N in bay))
				continue
			if(length(N.contents))
				continue
			N.make_wall()
			break


// --- Roaming pack: 3-5 of the same mob spawn as a group on the layer
// and wander together until they find a player. Replaces the older
// monster_swarm event — packs have a visible source (the pack moves
// as a unit, not random tile spawns) and one-shot semantics so
// players can actually clear them.
/datum/quarry_event/roaming_pack
	name = "Roaming Pack"
	weight = 10
	min_danger = QUARRY_DANGER_RESTLESS
	cooldown = 5 MINUTES

/datum/quarry_event/roaming_pack/fire(datum/quarry_layer/L)
	var/list/aggregated = _quarry_aggregate_features(L.feature_types, L)
	var/list/mob_table = aggregated["mob_table"]
	if(!length(mob_table))
		return
	var/mob_type = pickweight(mob_table)
	if(!mob_type)
		return

	// Find a cluster of floor tiles far from all players to spawn on.
	// We pick a far seed tile and spawn the pack on its neighbors.
	var/turf/seed = pick_far_floor(L, 12)
	if(!seed)
		// Fallback: any floor that isn't in the bay or occupied.
		seed = pick_layer_floor(L)
	if(!seed)
		return

	// Loud localized rustling — players nearby hear it directly,
	// distant players hear the muted version through the sound system's
	// falloff. The mobs themselves announce themselves when seen.
	playsound(seed, 'sound/effects/rustle4.ogg', 90, 1)

	var/pack_size = rand(3, 5)
	var/spawned = 0
	var/list/candidates = list(seed)
	for(var/dir in GLOB.cardinal)
		var/turf/N = get_step(seed, dir)
		if(istype(N, /turf/simulated/floor) && !length(N.contents))
			candidates += N
	while(spawned < pack_size && length(candidates))
		var/turf/T = candidates[1]
		candidates.Cut(1, 2)
		new mob_type(T)
		spawned++


// --- Stalker: single elite mob from a depth-appropriate roster spawns
// far from any player. Only one alive per layer at a time. Single
// announcement at spawn, then nothing — players hear footsteps and
// discover what hunts them on their own.
/datum/quarry_event/stalker
	name = "Stalker"
	weight = 6
	min_danger = QUARRY_DANGER_RESTLESS
	cooldown = 8 MINUTES

/datum/quarry_event/stalker/fire(datum/quarry_layer/L)
	// Refuse if a stalker is already prowling this layer.
	if(L.active_stalker && !QDELETED(L.active_stalker) && L.active_stalker.stat != DEAD)
		return
	var/stalker_type = quarry_stalker_type_for_depth(L.depth)
	if(!stalker_type)
		return
	var/turf/spawn_tile = pick_far_floor(L, 16)
	if(!spawn_tile)
		return
	var/mob/living/S = new stalker_type(spawn_tile)
	L.active_stalker = S
	// No announcement — players discover the stalker when they meet it.
	// A subtle distant snarl on spawn so they have *some* chance to
	// suspect what's coming.
	playsound(spawn_tile, 'sound/voice/shriek1.ogg', 25, 1)


// --- Pump malfunction: drains a running pump's cell. ----------------
/datum/quarry_event/pump_malfunction
	name = "Pump Malfunction"
	weight = 8
	min_danger = QUARRY_DANGER_DANGEROUS

/datum/quarry_event/pump_malfunction/fire(datum/quarry_layer/L)
	var/list/pumps = list()
	for(var/obj/machinery/pump/P in GLOB.machines)
		if(P.z == L.z && P.on && P.cell?.charge)
			pumps += P
	if(!length(pumps))
		return
	var/obj/machinery/pump/P = pick(pumps)
	// Loud sparking + the pump turning off (visible state change) tells
	// the story. The owner will figure out which pump from the lack
	// of running noise and the dead cell.
	playsound(P, 'sound/effects/sparks3.ogg', 80, 1)
	P.visible_message(span_warning("\The [P] shudders, sparks, and dies."))
	SSquarry.emit_noise(get_turf(P), QUARRY_NOISE_VENT, P)
	P.cell.charge = 0
	P.cell.update_icon()
	P.set_state(FALSE, message = FALSE)


// === SS DRIVER =======================================================

/datum/controller/subsystem/quarry
	/// Cache of /datum/quarry_event instances, one per subtype. Built
	/// at Initialize. Read-only at runtime.
	var/list/datum/quarry_event/events = list()
	/// Per-layer per-event-type last-fire timestamps, used for the
	/// per-event cooldown. Keyed "[depth_str]|[event_type_string]".
	var/list/event_cooldowns = list()


/datum/controller/subsystem/quarry/proc/init_events()
	events = list()
	for(var/event_type in subtypesof(/datum/quarry_event))
		events += new event_type()


/// Per SS-tick driver. For each loaded layer with at least one
/// player, roll an event with probability scaling from danger.
/datum/controller/subsystem/quarry/proc/tick_layer_events()
	if(!length(events))
		return
	for(var/key in layers)
		var/datum/quarry_layer/L = layers[key]
		if(!L?.loaded || L.unloading)
			continue
		if(is_layer_empty(L.z))
			continue
		if(!prob(100 * QUARRY_EVENT_BASE_CHANCE * (L.danger / 100)))
			continue
		var/datum/quarry_event/E = pick_event_for(L)
		if(!E)
			continue
		event_cooldowns["[L.depth]|[E.type]"] = world.time + E.cooldown
		E.fire(L)


/// Pick a weighted-random event eligible for the layer's current
/// danger level and not on cooldown. Returns null if none fit.
/datum/controller/subsystem/quarry/proc/pick_event_for(datum/quarry_layer/L)
	var/list/eligible = list()
	for(var/datum/quarry_event/E as anything in events)
		if(L.danger < E.min_danger || L.danger >= E.max_danger)
			continue
		var/cd_key = "[L.depth]|[E.type]"
		if(event_cooldowns[cd_key] && event_cooldowns[cd_key] > world.time)
			continue
		eligible[E] = E.weight
	if(!length(eligible))
		return null
	return pickweight(eligible)
