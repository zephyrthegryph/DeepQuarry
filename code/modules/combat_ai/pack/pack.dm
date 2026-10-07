// /datum/ai_pack: the unit of thinking (doc/rewrite/ai_packs.md B3). The brain is the unit of acting; a pack owns what several brains
// should do once: perceive (perception.dm), choose targets (targeting.dm) and find paths (flowfield.dm). Every brain is in a pack; a lone mob
// is a pack of one, and a pack of one passes every tactic test the old per-brain code did.
//
// Membership is a two-way link (members <-> brain.pack). A faction's pack_join_radius (0 by default: nobody forms packs) lets packs form: a new brain
// joins the pack whose leader is within pack_join_radius of it, and the pack's upkeep every PACK_UPKEEP_INTERVAL merges packs whose leaders have come
// within that radius and splits off members that fell more than pack_leave_radius from their leader (the two radii are the hysteresis). A pack with
// no member left deletes itself. A pack of a faction that forms no packs has no upkeep timer at all.
//
// Tracing: pack formation, joins, leaves, merges, splits, perception passes and target assignments are all written by pack.trace() when the
// pack (any member's brain `traced`) or GLOB.ai_trace_all asks for it.

/// Packs made since boot (tests and the trace read these).
GLOBAL_VAR_INIT(ai_pack_serial, 0)
GLOBAL_VAR_INIT(ai_pack_merges, 0)
GLOBAL_VAR_INIT(ai_pack_splits, 0)

/// Something near a pack moved, a member was hurt or heard: perceive soon (coalesced to one run per window).
ACTION(ai_pack_stir, FIXED, notice = /datum/notice/ai_pack_stirred)

/datum/ai_pack
	/// Which pack this is, for traces and for choosing which of two merging packs survives (the older one).
	var/serial = 0
	/// The faction every member shares (a pack never mixes factions).
	var/faction_key = null
	/// The brains in the pack (a link: brain.pack is the other end).
	var/list/members = null
	/// The member with the highest authority (elect_leader()); null in an empty pack.
	var/datum/ai_brain/leader = null
	/// TRUE while the pack's upkeep runs: its faction forms packs (pack_join_radius > 0). A pack of one in a faction that forms none has no timer at all.
	var/needs_upkeep = FALSE
	/// Perception state (perception.dm).
	var/list/sightings = null     // ref text of a mob => list(spotter ref text, first seen at, seen, last classified at)
	var/list/sighted = null       // the mobs sightings names (a relation list: a deleted mob leaves it)
	var/list/covered_ids = null   // the chunk ids watched now
	var/list/chunk_tokens = null  // the chunk datums watched now
	EXPIRY_DECLARE(last_perceived_at)
	/// Perception passes this pack made (tests and the trace).
	var/perceptions = 0
	/// Line-of-sight checks made by those passes, and view() builds behind them.
	var/los_checks = 0
	var/view_builds = 0

TRACKED(/datum/ai_pack, needs_upkeep)

CAPABILITIES(/datum/ai_pack)
	links(/datum/ai_pack::members, /datum/ai_brain::pack, a_many = TRUE)
	ref_one(nameof(leader))
	ref_many(nameof(sighted))
	on_notice(/datum/notice/ai_pack_stirred, coalesce(PROC_REF(perceive_interval)), then(PROC_REF(perceive_run)))
	every(PACK_UPKEEP_INTERVAL, then(PROC_REF(upkeep_run)), when = nameof(needs_upkeep))

/datum/ai_pack/New(faction)
	. = ..()
	serial = ++GLOB.ai_pack_serial
	faction_key = faction
	var/datum/faction_data/data = dq_faction_data_for(faction)
	if(data.pack_join_radius > 0)
		set_needs_upkeep(TRUE)

/// The pack is going away (empty, or merged into another): the chunk watches are dropped; its timers die with it.
/datum/ai_pack/on_destroy(force)
	. = ..()
	drop_chunk_watches()

/// The faction data of this pack's faction (the radii, the alert delay and the doctrine).
/datum/ai_pack/proc/faction_data()
	return dq_faction_data_for(faction_key)

/// Writes one debug line when the pack (any member's brain `traced`) or every brain (GLOB.ai_trace_all) is traced.
/datum/ai_pack/proc/trace(text)
	if(!GLOB.ai_trace_all)
		var/any = FALSE
		for(var/datum/ai_brain/B as anything in members)
			if(B.traced)
				any = TRUE
				break
		if(!any)
			return
	log_game("AI pack #[serial] ([faction_key || "no faction"], [length(members)] member[length(members) == 1 ? "" : "s"]): [text]")

/// The members that are alive and driving a mob (the ones that perceive and act).
/datum/ai_pack/proc/live_members()
	. = list()
	for(var/datum/ai_brain/B as anything in members)
		var/mob/living/L = B.holder
		if(L && !QDELETED(L) && L.stat < DEAD && L.loc)
			. += B

/// The highest relevance (STAT_RELEVANCE) of any member's mob: the pack is as relevant as its most relevant member.
/datum/ai_pack/proc/pack_relevance()
	. = RELEVANCE_NONE
	for(var/datum/ai_brain/B as anything in members)
		if(B.holder)
			. = max(., stat_value(B.holder, STAT_RELEVANCE))

// ---------------------------------------------------------------------------
// Membership
// ---------------------------------------------------------------------------

/// `B` joins this pack (leaving its old one). The first trigger of perception is raised so a new member is known to the pack at once.
/datum/ai_pack/proc/add_member(datum/ai_brain/B)
	if(!B || QDELETED(B) || (B in members))
		return
	var/datum/ai_pack/old = B.pack
	if(old && old != src)
		old.remove_member(B, "joined pack #[serial]")
	rel_add(src, nameof(members), B)
	trace("[B.holder] joined ([B.holder?.type])")
	sync_standings()
	elect_leader()
	stir("member joined")

/// `B` leaves; an empty pack deletes itself, otherwise the leader is re-elected.
/datum/ai_pack/proc/remove_member(datum/ai_brain/B, reason)
	if(!(B in members))
		return
	rel_remove(src, nameof(members), B)
	if(B.holder && !QDELETED(B.holder) && faction_key)
		unstanding(B.holder, faction_key, src)
	trace("[B.holder] left ([reason])")
	sync_standings()
	if(!length(members))
		trace("empty, deleted")
		qdel(src)
		return
	elect_leader()

/// Re-elects the leader: the member with the highest authority (brain.authority()), the oldest on a tie. The leader is what the pack's radii are measured from.
/datum/ai_pack/proc/elect_leader()
	var/datum/ai_brain/best = null
	var/best_score = -INFINITY
	for(var/datum/ai_brain/B as anything in members)
		var/score = B.authority()
		if(score > best_score)
			best_score = score
			best = B
	if(best == leader)
		return
	var/datum/ai_brain/old = leader
	if(best)
		rel_set(src, nameof(leader), best)
	else
		rel_clear(src, nameof(leader))
	trace("leader [best?.holder || "none"] (was [old?.holder || "none"])")

/// Raises the pack's perception trigger (coalesced: any number of stirs within a window give one pass).
/datum/ai_pack/proc/stir(why)
	if(QDELETED(src))
		return
	PUBLISH(src, ai_pack_stir)

// ---------------------------------------------------------------------------
// Brain side: every brain is in a pack
// ---------------------------------------------------------------------------

/datum/ai_brain
	/// The pack this brain is in (a link; null only while it is dead, being deleted, or before it has one).
	var/datum/ai_pack/pack = null
	/// world.time the brain was made: the seniority half of its authority.
	var/born_at = 0

/// The brain's weight in a leader election (doc ai_packs.md B6): health fraction (0..20) plus seniority (0..10); roles and traits add to it.
/datum/ai_brain/proc/authority()
	var/score = 0
	var/mob/living/L = holder
	if(L && !QDELETED(L))
		score += clamp(L.vitality(), 0, 1) * 20
	score += clamp((world.time - born_at) / (10 MINUTES), 0, 1) * 10
	return score

/// Puts this brain in a pack: the pack of the nearest leader within its faction's join radius, else a pack of its own.
/datum/ai_brain/proc/seek_pack()
	if(QDELETED(src) || !holder || QDELETED(holder) || holder.stat >= DEAD)
		return
	var/faction = holder.faction
	var/datum/faction_data/data = dq_faction_data_for(faction)
	if(data.pack_join_radius > 0 && !(holder.client && !autopilot))
		var/datum/ai_pack/found = nearest_pack_within(data.pack_join_radius)
		if(found)
			found.add_member(src)
			return
	if(pack && pack.faction_key == faction && length(pack.members) == 1)
		return
	var/datum/ai_pack/solo = new /datum/ai_pack(faction)
	solo.add_member(src)

/// The pack of the nearest other brain's leader (same faction, a living non-player mob) within `radius` tiles of this brain, or null.
/datum/ai_brain/proc/nearest_pack_within(radius)
	var/turf/T = get_turf(holder)
	if(!T)
		return null
	var/datum/ai_pack/best = null
	var/best_dist = INFINITY
	var/seen = list()
	for(var/datum/mob_chunk/C as anything in mob_chunks_around(T, radius))
		for(var/mob/living/L as anything in living_in_chunk(C.id))
			var/datum/ai_brain/other = L.ai_brain
			if(!other || other == src || QDELETED(other) || !other.pack || other.pack == pack || L.stat >= DEAD)
				continue
			if(other.pack.faction_key != holder.faction || (L.client && !other.autopilot))
				continue
			var/datum/ai_pack/P = other.pack
			if(seen[P])
				continue
			seen[P] = TRUE
			var/mob/living/lead = P.leader?.holder
			if(!lead || lead.z != holder.z)
				continue
			var/d = get_dist(holder, lead)
			if(d <= radius && d < best_dist)
				best_dist = d
				best = P
	return best

/// Leaves the pack (dead, deleted, taken over by a player); the pack deletes itself when this was its last member.
/datum/ai_brain/proc/leave_pack(reason)
	var/datum/ai_pack/P = pack
	if(P && !QDELETED(P))
		P.remove_member(src, reason)
	else
		rel_clear(src, nameof(pack))

/// Raises the pack's perception trigger.
/datum/ai_brain/proc/stir_pack(why)
	pack?.stir(why)

// ---------------------------------------------------------------------------
// Upkeep: merges, splits, chunk re-cover
// ---------------------------------------------------------------------------

/datum/ai_pack/proc/upkeep_run(datum/act/timer/A)
	upkeep()

/// One upkeep pass: split off members beyond the leave radius of the leader, merge with packs whose leaders are within the join radius, re-cover chunks.
/datum/ai_pack/proc/upkeep()
	if(QDELETED(src) || !length(members))
		return
	var/datum/faction_data/data = faction_data()
	var/mob/living/lead = leader?.holder
	if(lead && !QDELETED(lead))
		for(var/datum/ai_brain/B as anything in members.Copy())
			var/mob/living/L = B.holder
			if(B == leader || !L || QDELETED(L) || B.is_tethered())
				continue
			if(L.z != lead.z || get_dist(L, lead) > data.pack_leave_radius)
				GLOB.ai_pack_splits++
				trace("split: [L] is [L.z == lead.z ? get_dist(L, lead) : "off-level"] tiles from leader [lead] (leave radius [data.pack_leave_radius])")
				B.leave_pack("beyond the leave radius")
				var/datum/ai_pack/solo = new /datum/ai_pack(B.holder.faction)
				solo.add_member(B)
		if(QDELETED(src))
			return
		merge_nearby(data)
	if(!QDELETED(src))
		cover_chunks()

/// Merges with the pack whose leader is within the join radius of this pack's leader: the smaller joins the larger (the older on a tie).
/datum/ai_pack/proc/merge_nearby(datum/faction_data/data)
	var/mob/living/lead = leader?.holder
	if(!lead || QDELETED(lead))
		return
	var/turf/T = get_turf(lead)
	if(!T)
		return
	var/list/checked = list()
	for(var/datum/mob_chunk/C as anything in mob_chunks_around(T, data.pack_join_radius))
		for(var/mob/living/L as anything in living_in_chunk(C.id))
			var/datum/ai_brain/other = L.ai_brain
			if(!other || QDELETED(other) || !other.pack || other.pack == src)
				continue
			var/datum/ai_pack/P = other.pack
			if(checked[P] || P.faction_key != faction_key)
				continue
			checked[P] = TRUE
			var/mob/living/their_lead = P.leader?.holder
			if(!their_lead || QDELETED(their_lead) || their_lead.z != lead.z || get_dist(their_lead, lead) > data.pack_join_radius)
				continue
			var/datum/ai_pack/big = src
			var/datum/ai_pack/small = P
			if(length(P.members) > length(members) || (length(P.members) == length(members) && P.serial < serial))
				big = P
				small = src
			GLOB.ai_pack_merges++
			trace("merge: pack #[small.serial] ([length(small.members)]) into #[big.serial] ([length(big.members)]); leaders [lead] and [their_lead]")
			for(var/datum/ai_brain/B as anything in small.members.Copy())
				big.add_member(B)
			return

/// Sworn members never split off (roles, B6). Overridden by the sworn role.
/datum/ai_brain/proc/is_tethered()
	return FALSE
