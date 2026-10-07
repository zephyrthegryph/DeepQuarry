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

/// The coalesce window of the pack's perception (every window gives one pass): the shortest any member's state asks for (states/states.dm): a calm pack
/// waits PACK_PERCEIVE_CALM, an alert, fleeing or regrouping member asks PACK_PERCEIVE_ACTIVE, an engaged one PACK_PERCEIVE_ACTIVE on screen and
/// PACK_PERCEIVE_OFFSCREEN off it.
/datum/ai_pack/proc/perceive_interval(datum/act/A)
	var/window = PACK_PERCEIVE_CALM
	for(var/datum/ai_brain/B as anything in members)
		window = min(window, B.state_window())
	return window

/datum/ai_pack/proc/perceive_run(datum/act/A)
	perceive()

/// A backstop for a brain's strategic tick: a pass when none has run for a window.
/datum/ai_pack/proc/perceive_if_due()
	if(!last_perceived_at || ELAPSED_SINCE(src, last_perceived_at, CLOCK_WORLD) >= perceive_interval(null))
		perceive()

/// `brains` ordered by their distance to `where`, nearest first (a stable insertion sort: the lists are a pack's size).
/datum/ai_pack/proc/nearest_first(list/brains, atom/where)
	var/list/ordered = list()
	var/list/dists = list()
	for(var/datum/ai_brain/B as anything in brains)
		var/d = get_dist(B.get_owner(), where)
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
		for(var/mob/living/V in view(B.vision_range, B.get_owner()))
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

	// 1. candidates: the living mobs in the chunks that cover the members' vision (each mob is in exactly one chunk)
	var/list/chunks = covering_chunks(live)
	cover_chunks(chunks)
	var/list/cands = list()
	for(var/datum/mob_chunk/C as anything in chunks)
		for(var/mob/living/L as anything in living_in_chunk(C.id))
			if(L.stat < DEAD)
				cands += L

	// 2-4. who is noted, who is seen
	var/datum/faction_data/data = faction_data()
	var/list/views = list()
	var/list/fresh = list()
	var/list/seen_mobs = list()
	var/list/seen_info = list()
	var/hostile_candidates = 0
	for(var/mob/living/L as anything in cands)
		var/list/in_range = null
		for(var/datum/ai_brain/B as anything in live)
			var/mob/living/owner = B.get_owner()
			if(owner != L && owner.z == L.z && get_dist(owner, L) <= B.vision_range)
				LAZYADD(in_range, B)
		if(!in_range)
			continue
		var/needs_los = FALSE
		for(var/datum/ai_brain/B as anything in in_range)
			if(B.disposition_to(L) <= DQ_DISPOSITION_HOSTILE)
				needs_los = TRUE
				break
		var/datum/ai_brain/spotter = in_range[1]
		var/seen = FALSE
		if(needs_los)
			hostile_candidates++
			for(var/datum/ai_brain/B as anything in (length(in_range) > 1 ? nearest_first(in_range, L) : in_range))
				if(member_sees(B, L, views))
					spotter = B
					seen = TRUE
					break
		var/key = REF(L)
		var/first_at = world.time
		var/list/old = sightings?[key]
		if(old && old[SIGHT_SEEN] && seen)
			first_at = old[SIGHT_FIRST_AT]
		var/list/info = list(REF(spotter), first_at, seen)
		fresh[key] = info
		seen_mobs += L
		seen_info += list(info)

	// knowledge: replace, relation-listing the mobs (only what changed)
	sightings = length(fresh) ? fresh : null
	rel_swap(src, nameof(sighted), seen_mobs)

	// 5-6. publish to each member, the differences only
	var/pending_alert = INFINITY
	var/changed_members = 0
	for(var/datum/ai_brain/B as anything in live)
		var/mob/living/me = B.get_owner()
		var/my_ref = REF(B)
		var/list/hostiles = list()
		var/list/friendlies = list()
		var/list/neutrals = list()
		for(var/i in 1 to length(seen_mobs))
			var/mob/living/L = seen_mobs[i]
			if(L == me)
				continue
			var/list/S = seen_info[i]
			var/disposition = B.disposition_to(L)
			if(disposition <= DQ_DISPOSITION_HOSTILE)
				if(!S[SIGHT_SEEN])
					continue
				if(S[SIGHT_SPOTTER] != my_ref)
					var/datum/ai_brain/spotter = locate(S[SIGHT_SPOTTER])
					var/remaining = data.alert_delay - (world.time - S[SIGHT_FIRST_AT])
					if(!spotter || QDELETED(spotter) || !spotter.get_owner() || get_dist(spotter.get_owner(), me) > data.comm_radius)
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

/// The chunks that cover the live members' vision, each once.
/datum/ai_pack/proc/covering_chunks(list/live)
	var/list/chunks = list()
	var/list/ids = list()
	for(var/datum/ai_brain/B as anything in live)
		var/turf/T = get_turf(B.get_owner())
		if(!T)
			continue
		for(var/datum/mob_chunk/C as anything in mob_chunks_around(T, B.vision_range))
			if(!(C.id in ids))
				ids += C.id
				chunks += C
	return chunks

/// Keeps the chunk watches on `chunks` (made when they change, so a member that walked into a new chunk is heard there).
/datum/ai_pack/proc/cover_chunks(list/chunks = null)
	chunks ||= covering_chunks(live_members())
	var/list/ids = list()
	for(var/datum/mob_chunk/C as anything in chunks)
		ids += C.id
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
	return rel_swap(src, var_name, want)

/// Brings the relation list `var_name` of `E` to `want` touching only the differences (rel_remove for what left, rel_add for what came). TRUE when anything changed.
/proc/rel_swap(datum/E, var_name, list/want)
	var/list/have = E.vars[var_name]
	var/changed = FALSE
	for(var/datum/D as anything in have?.Copy())
		if(!(D in want))
			rel_remove(E, var_name, D)
			changed = TRUE
	for(var/datum/D as anything in want)
		if(!(D in have))
			rel_add(E, var_name, D)
			changed = TRUE
	return changed

/// A pass changed what this brain knows: the event that re-picks its behaviour.
/datum/ai_brain/proc/perception_changed()
	trace("perception changed: [length(model.visible_hostiles)] hostile(s), [length(model.visible_friendlies)] friendly(ies)")
	update_primary_threat()
	assess_state()
	PUBLISH(src, ai_perceive)
	invalidate_selection()
