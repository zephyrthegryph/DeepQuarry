// Standings (doc/rewrite/ai_packs.md B5): what a brain thinks of another mob is standing_toward() (code/engine/stats/standings.dm), a composition of rows
// that providers place on the mob. disposition_to() reads it; the old per-brain `personal` list and the per-call faction_data lookups are gone.
//
// Providers, by priority (the highest wins; on a tie the most hostile):
//   faction_relations  -1/0/1  the faction tables (data) as base stance: an ANY row (-1), a row per faction in the table and for the mob's own (0), and a
//                              PLAYERS row (1, so a player's standing is still player_disposition and not its faction's). Source SRC_AI_FACTION.
//   pack_member        50      ALLY toward the pack's faction while the pack has more than one member. Source: the pack (released when it is deleted).
//   serves(lord)       55      ALLY toward the lord, and the lord's own rows (B6). Source: the lord.
//   grudges            60      a mob that hurt, taunted or was given to the brain: HOSTILE (or what add_personal() says) for DQ_GRUDGE_DURATION. One per
//                              subject (the source is the brain), released when the brain is.
//   effects            80      tame, charm, pacify: place_effect_standing(): whatever the effect sets, released when the effect datum is.
//   admin              100     admin_standing(): anything, until released.

/// A DQ_DISPOSITION_* as a standing value (the engine's scale: lower is more hostile, STANDING_NEUTRAL 0).
/proc/dq_disposition_standing(disposition)
	switch(disposition)
		if(DQ_DISPOSITION_NEMESIS)
			return STANDING_HOSTILE * 1.5
		if(DQ_DISPOSITION_HOSTILE)
			return STANDING_HOSTILE
		if(DQ_DISPOSITION_WARY)
			return STANDING_WARY
		if(DQ_DISPOSITION_NEUTRAL)
			return STANDING_NEUTRAL
		if(DQ_DISPOSITION_FRIENDLY)
			return STANDING_FRIENDLY
		if(DQ_DISPOSITION_ALLY)
			return STANDING_ALLY
	return STANDING_NEUTRAL

/// A standing value as a DQ_DISPOSITION_* (the nearest of the six).
/proc/dq_standing_disposition(value)
	if(value <= STANDING_HOSTILE * 1.25)
		return DQ_DISPOSITION_NEMESIS
	if(value <= STANDING_HOSTILE * 0.75)
		return DQ_DISPOSITION_HOSTILE
	if(value <= STANDING_WARY * 0.5)
		return DQ_DISPOSITION_WARY
	if(value < STANDING_FRIENDLY * 0.5)
		return DQ_DISPOSITION_NEUTRAL
	if(value < STANDING_ALLY * 0.75)
		return DQ_DISPOSITION_FRIENDLY
	return DQ_DISPOSITION_ALLY

/datum/ai_brain
	/// The faction and ai_attack_on_sight the faction rows were placed for; disposition_to() re-places them when either changed.
	var/standings_faction = null
	var/standings_aggro = null
	/// The subjects the faction rows are toward (so they can be released).
	var/list/standings_keys = null
	/// "[REF(mob)]|faction|client" => the disposition standing_toward() gave, dropped whenever a standing row of the mob changes (standing_changed). A pack pass
	/// asks for every pair of its members and sightings, so the answer is remembered; the key carries what the engine's own cache checks (the subject's
	/// faction and whether a player has it).
	var/list/disposition_memo = null

/// TRUE when the mob's faction or hostile-on-sight flag is not what the faction rows were placed for.
/datum/ai_brain/proc/standings_stale()
	if(isnull(standings_aggro))
		return TRUE
	return holder.faction != standings_faction || standings_aggro != aggro_on_sight()

/// Does the mob attack strangers on sight (a simple mob's ai_attack_on_sight): it turns a table's NEUTRAL into HOSTILE for other factions.
/datum/ai_brain/proc/aggro_on_sight()
	var/mob/living/simple_mob/SM = holder
	return istype(SM) && SM.ai_attack_on_sight ? TRUE : FALSE

/// The faction_relations provider: places the rows of the mob's faction table (and defaults) as base standings.
/datum/ai_brain/proc/place_faction_rows()
	if(!holder || QDELETED(holder))
		return
	for(var/key in standings_keys)
		unstanding(holder, key, SRC_AI_FACTION)
	standings_keys = list()
	disposition_memo = null
	var/faction = holder.faction
	var/aggro = aggro_on_sight()
	standings_faction = faction
	standings_aggro = aggro
	var/datum/faction_data/data = dq_faction_data_for(faction)
	var/list/table = TYPE_TABLE_GET(data, get_relationships)
	// The ANY row is the default; the PLAYERS row is player_disposition, above the faction rows (a player is judged as a player).
	faction_row(STANDING_ANY, data.default_disposition, -1, aggro)
	faction_row(STANDING_PLAYERS, data.player_disposition, 1, aggro)
	for(var/other_faction in table)
		faction_row(other_faction, table[other_faction], 0, aggro)
	if(faction)
		// the mob's own faction: ALLY when the faction is registered (a mate), else whatever the default says, never turned hostile by aggro
		faction_row(faction, data.faction_key == faction ? DQ_DISPOSITION_ALLY : data.default_disposition, 0, FALSE)

/// One faction-table row. A NEUTRAL stranger becomes HOSTILE when the mob attacks on sight.
/datum/ai_brain/proc/faction_row(subject, disposition, priority, aggro)
	if(aggro && disposition == DQ_DISPOSITION_NEUTRAL)
		disposition = DQ_DISPOSITION_HOSTILE
	if(standing(holder, toward = subject, value = dq_disposition_standing(disposition), source = SRC_AI_FACTION, priority = priority, reason = "faction table"))
		LAZYOR(standings_keys, subject)

/datum/ai_brain/proc/disposition_to(mob/other)
	if(!other || other == holder)
		return DQ_DISPOSITION_ALLY
	if(standings_stale())
		place_faction_rows()
	var/key = "[REF(other)]|[other.faction]|[other.client ? 1 : 0]"
	var/memo = disposition_memo?[key]
	if(!isnull(memo))
		return memo
	var/result = dq_standing_disposition(standing_toward(holder, other))
	LAZYSET(disposition_memo, key, result)
	return result

/// A standing row of the mob changed (placed, replaced, released, expired, source deleted): what was remembered is stale.
/datum/ai_brain/proc/standings_changed(datum/act/A)
	disposition_memo = null

/// The grudges provider: this brain thinks `disposition` of `other` for `duration` deciseconds (0: until released), priority AI_STANDING_GRUDGE. One per subject.
/// (The old add_personal(): the name stays for its callers; a row is a grudge whatever the value.)
/datum/ai_brain/proc/add_personal(mob/other, disposition, duration = DQ_GRUDGE_DURATION, reason = null)
	if(!other || !holder || QDELETED(holder))
		return
	if(duration < 0) // an entry that is over before it starts: nothing to hold, and what was held toward them goes
		unstanding(holder, other, src)
		return
	standing(holder, toward = other, value = dq_disposition_standing(disposition), source = src, lasts = duration ? duration : null, priority = AI_STANDING_GRUDGE, reason = reason)
	trace("grudge: [other] [disposition] for [duration ? "[duration] ds" : "good"] ([reason || "no reason"])")
	selection_dirty = TRUE

/// This brain's own row toward `other` (a grudge or a gift), or null.
/datum/ai_brain/proc/grudge_value(mob/other)
	var/datum/stat_record/rec = holder?.rx?.stats
	if(!rec || !other)
		return null
	var/list/row = stat_hold_find(rec, HOLD_STANDING, src, standing_key(other, FALSE))
	return row ? row[H_VALUE] : null

/// The effects provider: a tame, charm or pacify effect (`source`, a live datum) makes the brain think `disposition` of `subject` at priority AI_STANDING_EFFECT.
/datum/ai_brain/proc/place_effect_standing(datum/source, subject, disposition, lasts = null)
	if(!holder || QDELETED(holder))
		return FALSE
	invalidate_selection()
	return standing(holder, toward = subject, value = dq_disposition_standing(disposition), source = source, lasts = lasts, priority = AI_STANDING_EFFECT, reason = "effect")

/// The admin provider: priority AI_STANDING_ADMIN, held until released (unstanding(holder, subject, SRC_AI_ADMIN)).
/datum/ai_brain/proc/admin_standing(subject, disposition)
	if(!holder || QDELETED(holder))
		return FALSE
	invalidate_selection()
	return standing(holder, toward = subject, value = dq_disposition_standing(disposition), source = SRC_AI_ADMIN, priority = AI_STANDING_ADMIN, reason = "admin")

/// The pack_member provider: while the pack has more than one member, every member regards the pack's faction as allies (priority AI_STANDING_PACK,
/// source the pack).
/datum/ai_pack/proc/sync_standings()
	for(var/datum/ai_brain/B as anything in members)
		if(!B.get_owner() || QDELETED(B.get_owner()) || !faction_key)
			continue
		if(length(members) > 1)
			standing(B.get_owner(), toward = faction_key, value = STANDING_ALLY, source = src, priority = AI_STANDING_PACK, reason = "pack member")
		else
			unstanding(B.get_owner(), faction_key, src)
