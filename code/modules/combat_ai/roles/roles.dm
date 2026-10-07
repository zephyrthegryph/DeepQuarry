// Authority, roles and orders (doc/rewrite/ai_packs.md B6).
//
// Leader: a pack's leader is the member with the highest authority (brain.authority()): the STAT_AI_AUTHORITY the member's mob holds, plus its health
// fraction (0 to 20) and its seniority (0 to 10). Holds on the stat: the lord role +100 (SRC_AI_LORD), the alpha trait +30 (SRC_AI_ALPHA). A change of the
// stat re-elects (the mob's on_change(STAT_AI_AUTHORITY)).
//
// Roles are capabilities granted to the mob:
//   lord      authority and the right to give orders (intend());
//   sworn     tethered to a lord: never splits off its pack; it joins the lord's pack and serves(lord);
//   sentinel  special sight: line of sight for dark or invisible targets is checked from sentinels first.
//
// serves(lord): the sworn member regards the lord as an ally and takes the lord's hostile standings as its own (priority AI_STANDING_SERVES, source
// the lord), re-synced when the lord's standings change. The rows go when the lord is deleted, and the sworn is freed when the lord dies.
//
// Orders are intents (intents.dm).

CAPABILITY_TYPE(ai_role_lord, CAP_AI_ROLE_LORD, /datum/capability/ai_role/lord, key = NONE)
CAPABILITY_TYPE(ai_role_sworn, CAP_AI_ROLE_SWORN, /datum/capability/ai_role/sworn, key = NONE)
CAPABILITY_TYPE(ai_role_sentinel, CAP_AI_ROLE_SENTINEL, /datum/capability/ai_role/sentinel, key = NONE)

/datum/capability/ai_role
	/// What holding the role adds to STAT_AI_AUTHORITY.
	var/authority = 0

/datum/capability/ai_role/lord
	authority = 100

/datum/capability/ai_role/lord/entries()
	return list()

/datum/capability/ai_role/sworn/entries()
	return list()

/datum/capability/ai_role/sentinel/entries()
	return list()

/// Authority adds up: roles and traits hold on it, sources never overlap.
/mob/living/proc/ai_authority_changed(datum/act/A)
	ai_brain?.pack?.elect_leader()

/// Gives the mob a role: the capability, and the authority it carries.
/datum/ai_brain/proc/grant_role(role_type)
	if(!holder || QDELETED(holder) || granted(holder, role_type))
		return
	grant(holder, role_type, src)
	var/datum/capability/ai_role/role = dq_ai_role_def(role_type)
	if(role.authority)
		hold(holder, STAT_AI_AUTHORITY, role.authority, SRC_AI_LORD, reason = "ai role")
	trace("role [role_type] granted")
	pack?.elect_leader()

/// Takes a role away.
/datum/ai_brain/proc/revoke_role(role_type)
	if(!holder || !granted(holder, role_type))
		return
	revoke(holder, role_type, src)
	var/datum/capability/ai_role/role = dq_ai_role_def(role_type)
	if(role.authority)
		release(holder, STAT_AI_AUTHORITY, SRC_AI_LORD)
	trace("role [role_type] revoked")
	pack?.elect_leader()

/datum/ai_brain/proc/has_role(role_type)
	return holder && granted(holder, role_type)

/// The alpha trait: +30 authority while it holds.
/datum/ai_brain/proc/set_alpha(on)
	if(!holder || QDELETED(holder))
		return
	if(on)
		hold(holder, STAT_AI_AUTHORITY, 30, SRC_AI_ALPHA, reason = "alpha")
	else
		release(holder, STAT_AI_AUTHORITY, SRC_AI_ALPHA)

/proc/dq_ai_role_def(role_type)
	var/static/list/defs = list()
	var/datum/capability/ai_role/def = defs[role_type]
	if(!def)
		def = new role_type
		defs[role_type] = def
	return def

/// Sworn members never split off their pack.
/datum/ai_brain/proc/is_tethered()
	return has_role(/datum/capability/ai_role/sworn)

/// The authority this brain brings to an election: what its mob holds on STAT_AI_AUTHORITY, plus health and seniority.
/datum/ai_brain/proc/authority()
	var/score = 0
	var/mob/living/L = holder
	if(L && !QDELETED(L))
		score += stat_value(L, STAT_AI_AUTHORITY)
		score += clamp(L.vitality(), 0, 1) * 20
	score += clamp(ELAPSED(src, born_at, CLOCK_WORLD) / (10 MINUTES), 0, 1) * 10
	return score

// ---------------------------------------------------------------------------
// serves(lord)
// ---------------------------------------------------------------------------

/datum/ai_brain
	/// The lord this brain serves, if sworn (a relation view).
	var/mob/living/lord = null

/// This brain swears to `new_lord`: it joins the lord's pack as sworn, takes the lord as an ally and its hostile standings as its own.
/datum/ai_brain/proc/serve(mob/living/new_lord)
	if(!new_lord || new_lord == holder || (lord == new_lord && has_role(/datum/capability/ai_role/sworn)))
		return
	rel_set(src, nameof(lord), new_lord)
	grant_role(/datum/capability/ai_role/sworn)
	var/datum/ai_pack/lords_pack = new_lord.ai_brain?.pack
	if(lords_pack && lords_pack != pack)
		lords_pack.add_member(src)
	sync_serves()
	observe(new_lord, /datum/notice/standing_changed, src, then(PROC_REF(lord_standings_changed)))
	trace("serves [new_lord]")

/// The lord's standings changed: the sworn takes them again.
/datum/ai_brain/proc/lord_standings_changed(datum/act/A)
	sync_serves()

/// The serves(lord) rows: ALLY toward the lord, and each hostile standing of the lord (a grudge, an order) as a row of this brain (source: the lord).
/datum/ai_brain/proc/sync_serves()
	var/mob/living/the_lord = lord
	if(!the_lord || QDELETED(the_lord) || !holder || QDELETED(holder))
		return
	standing(holder, toward = the_lord, value = STANDING_ALLY, source = the_lord, priority = AI_STANDING_SERVES, reason = "serves")
	var/datum/stat_record/rec = the_lord.rx?.stats
	for(var/list/row as anything in rec?.holds)
		if(row[H_STAT] != HOLD_STANDING || row[H_VALUE] > STANDING_HOSTILE || row[H_SOURCE] == holder)
			continue
		var/subject = standing_row_subject(row)
		if(!subject || subject == holder)
			continue
		standing(holder, toward = subject, value = row[H_VALUE], source = the_lord, priority = AI_STANDING_SERVES, reason = "serves")

/// The subject a standing row is toward: the mob (or datum) its key names, or the faction/special key text.
/proc/standing_row_subject(list/row)
	var/key = row[H_KEY]
	if(!istext(key))
		return null
	if(copytext(key, 1, 3) == "d:")
		return locate(copytext(key, 3))
	if(copytext(key, 1, 3) == "f:")
		return copytext(key, 3)
	return key

/// Frees the brain from its lord: no longer sworn, the borrowed rows go, and it makes a pack of its own.
/datum/ai_brain/proc/unserve()
	var/mob/living/old = lord
	if(!old)
		return
	unobserve(old, /datum/notice/standing_changed, src)
	rel_clear(src, nameof(lord))
	if(holder && !QDELETED(holder))
		unstanding(holder, old, old)
		var/datum/stat_record/rec = holder.rx?.stats
		for(var/list/row as anything in rec?.holds?.Copy())
			if(row[H_STAT] == HOLD_STANDING && row[H_SOURCE] == old)
				stat_hold_remove(holder, rec, row)
	revoke_role(/datum/capability/ai_role/sworn)
	trace("no longer serves [old]")
	if(!QDELETED(src) && holder && holder.stat < DEAD)
		leave_pack("freed from lord")
		seek_pack()

/// A lord died: everyone sworn to it is freed.
/datum/ai_brain/proc/release_servants()
	for(var/datum/ai_brain/B as anything in pack?.members?.Copy())
		if(B != src && B.lord == holder)
			B.unserve()
