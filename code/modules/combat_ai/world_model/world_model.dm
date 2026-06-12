// /datum/world_model — per-brain perception cache.
//
// Refreshed once per slow tick from the brain. Behaviors READ this; they never
// run view()/range()/orange() themselves. Cuts the AI cost from O(behaviors ×
// tick) to one perception call per slow tick per brain — and for a mob in a pack,
// down to a shared per-pack scan its lord runs once (update_perception buckets
// from /datum/ai_lord/perceived instead of scanning per mob).
//
// All lists are either reused-in-place (visible_*) or lazy (events/sounds),
// per the project's list-allocation rules.

/datum/world_model
	/// Weak ref to the mob we observe for, kept weak so we never block GC.
	var/datum/weakref/owner_ref = null

	/// Last fully-populated perception lists. Held mobs/objs only; never turfs.
	/// Reused — Cut() instead of reallocating.
	var/list/visible_hostiles = null   // mobs the brain wants to engage
	var/list/visible_friendlies = null // mobs the brain wants to protect/heal
	var/list/visible_neutrals = null   // everyone else in view (for awareness only)

	/// Lazylists — usually empty, so we pay no list-allocation cost most of the time.
	var/list/recent_damage_events = null // each entry: list(amount, type, attacker_ref, when)
	var/list/heard_sounds = null         // each entry: list(turf_ref, type, when)
	var/list/known_hazards = null        // each entry: list(atom_ref, severity, expires)

	/// One-slot caches (refs).
	var/datum/weakref/last_attacker = null
	var/atom/last_known_threat_turf = null

	/// world.time of last perception refresh.
	var/last_update = 0

	/// Cumulative damage in the last DQ_DAMAGE_HISTORY_CAP entries. Updated on
	/// damage events, decayed by trim_old_damage.
	var/recent_damage_total = 0

/datum/world_model/New(mob/living/owner)
	if(owner)
		owner_ref = WEAKREF(owner)
	visible_hostiles = list()
	visible_friendlies = list()
	visible_neutrals = list()

/datum/world_model/Destroy()
	owner_ref = null
	last_attacker = null
	last_known_threat_turf = null
	visible_hostiles = null
	visible_friendlies = null
	visible_neutrals = null
	recent_damage_events = null
	heard_sounds = null
	known_hazards = null
	return ..()

/datum/world_model/proc/get_owner()
	return owner_ref?.resolve()

/// Refreshes the visible_* buckets. Called from /datum/ai_brain/handle_strategicals.
///
/// A mob in a pack reads its lord's one shared scan (cheap distance + disposition
/// filtering) instead of running its own view — one perception scan per pack per
/// tick, not one per mob. A lordless mob (or one whose lord's scan has gone stale)
/// scans its own surroundings.
///
/// Scanning uses dview (a lighting-independent view) rather than view(): a cave
/// predator senses prey in pitch darkness, but opacity still blocks it, so walls
/// hide you. Plain view() made AI blind in unlit quarry caves — they only noticed
/// a player once you were lit or nearly adjacent.
/datum/world_model/proc/update_perception(datum/ai_brain/brain)
	var/mob/living/owner = get_owner()
	if(!owner || !brain)
		return

	visible_hostiles.Cut()
	visible_friendlies.Cut()
	visible_neutrals.Cut()

	var/range = brain.vision_range
	var/datum/ai_lord/lord = brain.lord
	if(lord && lord.perception_fresh())
		// Pack member: bucket from the lord's shared scan. Range-gate so an edge
		// member doesn't perceive past its own vision, and re-check liveness since
		// the scan may be up to LORD_PERCEPTION_TTL old.
		var/turf/ot = get_turf(owner)
		for(var/mob/living/M as anything in lord.perceived)
			if(M == owner || QDELETED(M) || M.stat >= DEAD)
				continue
			if(get_dist(ot, M) > range)
				continue
			bucket_mob(brain, M)
	else
		for(var/mob/living/M in dview(range, get_turf(owner)))
			if(M == owner || M.stat >= DEAD)
				continue
			bucket_mob(brain, M)

	last_update = world.time
	trim_old_damage()
	trim_old_sounds()
	trim_old_hazards()

/// Sort one mob into the visible_* buckets by the brain's disposition toward it.
/// Shared by the lord-scan and self-scan perception paths.
/datum/world_model/proc/bucket_mob(datum/ai_brain/brain, mob/living/M)
	var/disposition = brain.disposition_to(M)
	if(disposition <= DQ_DISPOSITION_HOSTILE)
		visible_hostiles += M
	else if(disposition >= DQ_DISPOSITION_FRIENDLY)
		visible_friendlies += M
	else
		visible_neutrals += M

/// Record an incoming hit. Called by the brain's damage signal handler.
/datum/world_model/proc/record_damage(amount, damagetype, atom/attacker)
	LAZYINITLIST(recent_damage_events)
	if(length(recent_damage_events) >= DQ_DAMAGE_HISTORY_CAP)
		// Drop oldest. Simple O(n) shift — list is tiny.
		var/dropped = recent_damage_events[1]
		recent_damage_events.Cut(1, 2)
		if(islist(dropped))
			recent_damage_total = max(0, recent_damage_total - dropped[1])
	recent_damage_events += list(list(amount, damagetype, WEAKREF(attacker), world.time))
	recent_damage_total += amount
	if(attacker)
		last_attacker = WEAKREF(attacker)
		last_known_threat_turf = get_turf(attacker)

/// Drop damage entries older than 10 seconds.
/datum/world_model/proc/trim_old_damage()
	if(!LAZYLEN(recent_damage_events))
		return
	var/cutoff = world.time - 10 SECONDS
	while(length(recent_damage_events) && recent_damage_events[1][4] < cutoff)
		var/list/entry = recent_damage_events[1]
		recent_damage_total = max(0, recent_damage_total - entry[1])
		recent_damage_events.Cut(1, 2)
	UNSETEMPTY(recent_damage_events)

/datum/world_model/proc/record_sound(turf/T, type)
	if(!T)
		return
	LAZYINITLIST(heard_sounds)
	heard_sounds += list(list(T, type, world.time))

/datum/world_model/proc/trim_old_sounds()
	if(!LAZYLEN(heard_sounds))
		return
	var/cutoff = world.time - 5 SECONDS
	while(length(heard_sounds) && heard_sounds[1][3] < cutoff)
		heard_sounds.Cut(1, 2)
	UNSETEMPTY(heard_sounds)

/datum/world_model/proc/record_hazard(atom/hazard, severity = 1, duration = 5 SECONDS)
	if(!hazard)
		return
	LAZYINITLIST(known_hazards)
	known_hazards += list(list(WEAKREF(hazard), severity, world.time + duration))

/datum/world_model/proc/trim_old_hazards()
	if(!LAZYLEN(known_hazards))
		return
	for(var/i = length(known_hazards), i >= 1, i--)
		var/list/entry = known_hazards[i]
		if(entry[3] < world.time)
			known_hazards.Cut(i, i + 1)
	UNSETEMPTY(known_hazards)

/datum/world_model/proc/get_last_attacker()
	return last_attacker?.resolve()
