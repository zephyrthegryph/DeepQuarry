// Pack perception (doc/rewrite/ai_packs.md B3): who is near, who sees whom, who has been told.
//
// A pack perceives once for all its members. A pass:
//   1. candidates: the living mobs standing in the chunks that cover the members' vision (living_in_chunk(): a per-chunk index, no view() scan);
//   2. friendlies and neutrals are noted without a line-of-sight check;
//   3. for a candidate some member treats as hostile, line of sight is checked nearest member first and stops at the first member that sees it. The
//      check is a lookup in that member's view(), built at most once per pass and only for a member that is asked (so a pack of one pays exactly
//      the view() the old per-brain pass paid, and a pack pays for the members it needed);
//   4. the pack's knowledge records who was seen, by whom and when, not what each member thinks of them: every member classifies a sighting with its own
//      disposition_to();
//   5. only the spotter knows a hostile sighting at once; the others learn after the faction's alert delay, within its communication radius;
//   6. each member's model is updated with the differences only.
//
// A pass runs from the stir trigger (chunk activity, a member hurt or heard) coalesced to one run per window (perceive_interval()), and from a brain's
// strategic backstop when the pack has not perceived for a window (perceive_if_due()). Nothing schedules a pass for a pack that nothing disturbs.

/// Perception passes by all packs, line-of-sight lookups they made, and view() builds behind them (tests count these).
GLOBAL_VAR_INIT(ai_pack_perceptions, 0)
GLOBAL_VAR_INIT(ai_pack_los_checks, 0)
GLOBAL_VAR_INIT(ai_pack_view_builds, 0)

/// The coalesce window of the pack's perception (every window gives one pass): a calm pack waits PACK_PERCEIVE_CALM, one that knows a hostile (alert) or
/// fights (engaged) perceives every PACK_PERCEIVE_ACTIVE, and an engaged pack with no member on a player's screen every PACK_PERCEIVE_OFFSCREEN.
/datum/ai_pack/proc/perceive_interval(datum/act/A)
	var/engaged = FALSE
	var/alert = FALSE
	for(var/datum/ai_brain/B as anything in members)
		if(B.primary_threat)
			engaged = TRUE
		if(length(B.model?.visible_hostiles))
			alert = TRUE
	if(engaged)
		return pack_relevance() >= RELEVANCE_VISIBLE ? PACK_PERCEIVE_ACTIVE : PACK_PERCEIVE_OFFSCREEN
	return alert ? PACK_PERCEIVE_ACTIVE : PACK_PERCEIVE_CALM

/datum/ai_pack/proc/perceive_run(datum/act/A)
	perceive()

/// A backstop for a brain's strategic tick: a pass when none has run for a window.
/datum/ai_pack/proc/perceive_if_due()
	if(!last_perceived_at || ELAPSED_SINCE(src, last_perceived_at, CLOCK_WORLD) >= perceive_interval(null))
		perceive()

/// `members` ordered by their distance to `where`, nearest first (members out of `range` of it are left out).
/datum/ai_pack/proc/nearest_first(list/brains, atom/where, ranged = TRUE)
	var/list/ordered = list()
	var/list/dists = list()
	for(var/datum/ai_brain/B as anything in brains)
		var/mob/living/L = B.holder
		if(L == where || L.z != where.z)
			continue
		var/d = get_dist(L, where)
		if(ranged && d > B.vision_range)
			continue
		var/at = 1
		while(at <= length(ordered) && dists[at] <= d)
			at++
		ordered.Insert(at, B)
		dists.Insert(at, d)
	return ordered

/// Does `B`'s mob see `L`? A lookup in B's view of living mobs (built once per pass, on the first ask), so it answers exactly as view() does for it.
/datum/ai_pack/proc/member_sees(datum/ai_brain/B, mob/living/L, list/views)
	los_checks++
	GLOB.ai_pack_los_checks++
	var/list/seen = views[B]
	if(!seen)
		seen = list()
		view_builds++
		GLOB.ai_pack_view_builds++
		for(var/mob/living/V in view(B.vision_range, B.holder))
			seen[V] = TRUE
		views[B] = seen
	return !!seen[L]

/// One perception pass for every member. `force` runs it even where no player could see (tests, a hand-driven brain).
/datum/ai_pack/proc/perceive(force = FALSE)
	if(QDELETED(src))
		return
	var/list/live = live_members()
	if(!length(live))
		return
	if(!force && pack_relevance() < RELEVANCE_NEAR)
		trace("perception parked: no member is relevant")
		return
	var/started = TICK_USAGE
	perceptions++
	GLOB.ai_pack_perceptions++
	EXPIRY_STAMP(src, last_perceived_at, CLOCK_WORLD)
	cover_chunks(live)

	// 1. candidates
	var/list/cands = list()
	var/list/chunk_done = list()
	for(var/datum/ai_brain/B as anything in live)
		var/turf/T = get_turf(B.holder)
		if(!T)
			continue
		for(var/datum/mob_chunk/C as anything in mob_chunks_around(T, B.vision_range))
			if(chunk_done["[C.id]"])
				continue
			chunk_done["[C.id]"] = TRUE
			for(var/mob/living/L as anything in living_in_chunk(C.id))
				if(L.stat < DEAD)
					cands[REF(L)] = L

	// 2-4. who is noted, who is seen
	var/datum/faction_data/data = faction_data()
	var/list/views = list()
	var/list/fresh = list()
	var/list/fresh_mobs = list()
	var/hostile_candidates = 0
	for(var/key in cands)
		var/mob/living/L = cands[key]
		var/list/near = nearest_first(live, L)
		if(!length(near))
			continue
		var/needs_los = FALSE
		for(var/datum/ai_brain/B as anything in near)
			if(B.disposition_to(L) <= DQ_DISPOSITION_HOSTILE)
				needs_los = TRUE
				break
		var/datum/ai_brain/spotter = near[1]
		var/seen = FALSE
		if(needs_los)
			hostile_candidates++
			for(var/datum/ai_brain/B as anything in near)
				if(member_sees(B, L, views))
					spotter = B
					seen = TRUE
					break
		var/first_at = world.time
		var/list/old = sightings?[key]
		if(old && old[SIGHT_SEEN] && seen)
			first_at = old[SIGHT_FIRST_AT]
		fresh[key] = list(REF(spotter), first_at, seen)
		fresh_mobs += L

	// knowledge: replace, relation-listing the mobs
	sightings = length(fresh) ? fresh : null
	rel_clear(src, nameof(sighted))
	for(var/mob/living/L as anything in fresh_mobs)
		rel_add(src, nameof(sighted), L)

	// 5-6. publish to each member, the differences only
	var/pending_alert = INFINITY
	var/changed_members = 0
	for(var/datum/ai_brain/B as anything in live)
		var/list/hostiles = list()
		var/list/friendlies = list()
		var/list/neutrals = list()
		for(var/mob/living/L as anything in sighted)
			if(L == B.holder)
				continue
			var/list/S = sightings[REF(L)]
			var/disposition = B.disposition_to(L)
			if(disposition <= DQ_DISPOSITION_HOSTILE)
				if(!S[SIGHT_SEEN])
					continue
				if(S[SIGHT_SPOTTER] != REF(B))
					var/datum/ai_brain/spotter = locate(S[SIGHT_SPOTTER])
					var/remaining = data.alert_delay - (world.time - S[SIGHT_FIRST_AT])
					if(!spotter || QDELETED(spotter) || !spotter.holder || get_dist(spotter.holder, B.holder) > data.comm_radius)
						continue
					if(remaining > 0)
						pending_alert = min(pending_alert, remaining)
						continue
				hostiles += L
			else if(disposition >= DQ_DISPOSITION_FRIENDLY)
				friendlies += L
			else
				neutrals += L
		if(B.model.publish_perception(hostiles, friendlies, neutrals))
			changed_members++
			B.perception_changed()
	if(pending_alert < INFINITY)
		after_unique(src, max(1, pending_alert), TYPE_PROC_REF(/datum/ai_pack, perceive_pending))
	GLOB.ai_brain_cost_ms += TICK_USAGE_TO_MS(started)
	trace("perceived: [length(live)] member(s), [length(cands)] candidate(s), [hostile_candidates] needing line of sight, [length(views)] view build(s), [length(fresh)] sighting(s), [changed_members] member(s) updated")

/// A delayed alert came due: another pass delivers it.
/datum/ai_pack/proc/perceive_pending()
	perceive()

/// Keeps the chunk watches on the chunks that cover the live members' vision (made when they change, so a member that walked into a new chunk is heard there).
/datum/ai_pack/proc/cover_chunks(list/live = null)
	live ||= live_members()
	var/list/ids = list()
	var/list/chunks = list()
	for(var/datum/ai_brain/B as anything in live)
		var/turf/T = get_turf(B.holder)
		if(!T)
			continue
		for(var/datum/mob_chunk/C as anything in mob_chunks_around(T, B.vision_range))
			if(!(C.id in ids))
				ids += C.id
				chunks += C
	if(!ai_pack_ids_differ(ids, covered_ids))
		return
	drop_chunk_watches()
	covered_ids = ids
	chunk_tokens = watch_mob_chunks(src, chunks, CHANGE_CHUNK_ANY_MOB, PROC_REF(chunk_stirred))
	trace("watching [length(ids)] chunk(s)")

/// TRUE when the two id lists differ (as sets).
/proc/ai_pack_ids_differ(list/a, list/b)
	if(length(a) != length(b))
		return TRUE
	for(var/x in a)
		if(!(x in b))
			return TRUE
	return FALSE

/datum/ai_pack/proc/drop_chunk_watches()
	if(chunk_tokens)
		chunk_tokens = unwatch_mob_chunks(src, chunk_tokens, CHANGE_CHUNK_ANY_MOB)
	covered_ids = null

/// A mob moved or appeared in a chunk the pack watches.
/datum/ai_pack/proc/chunk_stirred(datum/mob_chunk/C, bits)
	stir("chunk activity")

/// Replaces this model's perception lists with the given ones, touching only the differences. TRUE when the hostile set (the one that decides what a brain does) changed.
/datum/world_model/proc/publish_perception(list/hostiles, list/friendlies, list/neutrals)
	visible_hostiles ||= list()
	visible_friendlies ||= list()
	visible_neutrals ||= list()
	var/hostiles_changed = swap_perceived(nameof(visible_hostiles), hostiles)
	var/others_changed = swap_perceived(nameof(visible_friendlies), friendlies)
	others_changed = swap_perceived(nameof(visible_neutrals), neutrals) || others_changed
	trim_old_damage()
	trim_old_sounds()
	trim_old_hazards()
	EXPIRY_STAMP(src, last_update, CLOCK_WORLD)
	return hostiles_changed || others_changed

/// One perception list brought to `want` by removing what is gone and adding what is new. TRUE when anything changed.
/datum/world_model/proc/swap_perceived(var_name, list/want)
	var/list/have = vars[var_name]
	var/changed = FALSE
	for(var/mob/living/M as anything in have.Copy())
		if(!(M in want))
			rel_remove(src, var_name, M)
			changed = TRUE
	for(var/mob/living/M as anything in want)
		if(!(M in have))
			rel_add(src, var_name, M)
			changed = TRUE
	return changed

/// A pass changed what this brain knows: the event that re-picks its behaviour.
/datum/ai_brain/proc/perception_changed()
	trace("perception changed: [length(model.visible_hostiles)] hostile(s), [length(model.visible_friendlies)] friendly(ies)")
	update_primary_threat()
	invalidate_selection()
