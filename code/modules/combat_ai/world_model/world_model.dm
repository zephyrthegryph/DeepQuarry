// /datum/world_model — per-brain perception cache.
//
// Refreshed once per slow tick from the brain. Behaviors READ this; they never
// run view()/range()/orange() themselves. Cuts the AI cost from O(behaviors ×
// tick) to one perception call per slow tick per brain, with the option to
// share results across faction-mates in the same cluster later.
//
// All lists are either reused-in-place (visible_*) or lazy (events/sounds),
// per the project's list-allocation rules.

/datum/world_model
	/// The mob we observe for (a relation view, so we never block GC).
	var/mob/living/owner = null

	/// Last fully-populated perception lists. Held mobs/objs only; never turfs.
	/// Reused — Cut() instead of reallocating.
	var/list/visible_hostiles = null   // mobs the brain wants to engage
	var/list/visible_friendlies = null // mobs the brain wants to protect/heal
	var/list/visible_neutrals = null   // everyone else in view (for awareness only)

	/// Lazylists — usually empty, so we pay no list-allocation cost most of the time.
	var/list/recent_damage_events = null // each entry: list(amount, type, attacker name, when)
	var/list/heard_sounds = null         // each entry: list(turf_ref, type, when)
	var/list/known_hazards = null        // each entry: list(hazard ref text, severity, expires); the hazard itself is in hazard_atoms
	/// The hazards known_hazards names (a relation list: a deleted hazard leaves it).
	var/list/hazard_atoms = null

	/// One-slot caches (relation views).
	var/atom/last_attacker = null
	var/tmp/atom/last_known_threat_turf

	/// world.time of last perception refresh.
	var/last_update = 0

	/// Cumulative damage in the last DQ_DAMAGE_HISTORY_CAP entries. Updated on
	/// damage events, decayed by trim_old_damage.
	var/recent_damage_total = 0

/datum/world_model/New(mob/living/owner)
	if(owner)
		rel_set(src, nameof(owner), owner)
	rel_clear(src, nameof(visible_hostiles))
	rel_clear(src, nameof(visible_friendlies))
	rel_clear(src, nameof(visible_neutrals))

/datum/world_model/proc/get_owner()
	return owner

/// Perceives now: the brain's pack runs a pass (perception is the pack's, pack/perception.dm), which updates this model with the differences.
/// Kept for callers that drive a brain by hand (tests, forced re-looks); a pack of one sees exactly what view() showed the brain.
/datum/world_model/proc/update_perception(datum/ai_brain/brain)
	var/mob/living/owner = get_owner()
	if(!owner || !brain)
		return
	brain.pack?.perceive(TRUE)

/// Record an incoming hit. Called by the brain's damage signal handler.
/datum/world_model/proc/record_damage(amount, injury_kind, atom/attacker)
	LAZYINITLIST(recent_damage_events)
	if(length(recent_damage_events) >= DQ_DAMAGE_HISTORY_CAP)
		// Drop oldest. Simple O(n) shift — list is tiny.
		var/dropped = recent_damage_events[1]
		recent_damage_events.Cut(1, 2)
		if(islist(dropped))
			recent_damage_total = max(0, recent_damage_total - dropped[1])
	recent_damage_events += list(list(amount, injury_kind, attacker ? "[attacker]" : null, world.time))
	recent_damage_total += amount
	if(attacker)
		rel_set(src, nameof(last_attacker), attacker)
		rel_set(src, nameof(last_known_threat_turf), get_turf(attacker))

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
	rel_add(src, nameof(hazard_atoms), hazard)
	known_hazards += list(list(ref(hazard), severity, world.time + duration))

/datum/world_model/proc/trim_old_hazards()
	if(!LAZYLEN(known_hazards))
		return
	for(var/i = length(known_hazards), i >= 1, i--)
		var/list/entry = known_hazards[i]
		var/atom/hazard = locate(entry[1])
		if(ELAPSED_SINCE(src, entry[3], CLOCK_WORLD) > 0 || !(hazard in hazard_atoms))
			known_hazards.Cut(i, i + 1)
			if(hazard in hazard_atoms)
				rel_remove(src, nameof(hazard_atoms), hazard)
	UNSETEMPTY(known_hazards)

/datum/world_model/proc/get_last_attacker()
	return last_attacker

/// the last_known_threat_turf this refers to (a relation view: null once it is deleted).
/datum/world_model/proc/last_known_threat_turf() as /atom
	return last_known_threat_turf

/// The perception lists are rebuilt from view() on every update_perception() call:
/// caches of other mobs, not relationships.
/datum/world_model/declared_cache_vars()
	var/list/L = ..()
	L = L ? L.Copy() : list()
	L["visible_hostiles"] = CACHE_ON_CHANGE(CHANGE_EXPLICIT)
	L["visible_friendlies"] = CACHE_ON_CHANGE(CHANGE_EXPLICIT)
	L["visible_neutrals"] = CACHE_ON_CHANGE(CHANGE_EXPLICIT)
	return L

CAPABILITIES(/datum/world_model)
	ref_many(nameof(hazard_atoms))
