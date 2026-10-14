// Orders (doc/rewrite/ai_packs.md B6): a lord or any member issues an intent to its pack, and members read it as part of deciding what to do.
//
//	intend(pack, /datum/ai_intent/retreat, subject, source = issuer, lasts = 8 SECONDS)
//
// An intent has a kind, an optional subject, a source (who gave it) and a lifetime. It is released when it runs out, when its issuer is deleted or dead, or
// when its pack is deleted. Members read the live ones through brain.active_intents(); a tactic's evaluate() decides what an intent means to it. Nothing acts
// on an intent by itself.

/// What an order is about: a retreat from the subject, a rally against it, a regroup on it.
/datum/ai_intent
	var/name = "intent"
	/// Who the order concerns (a relation view).
	var/atom/subject = null
	/// Who gave it (a relation view): the order ends with them.
	var/datum/source = null
	/// world.time it lapses; 0: never.
	EXPIRY_DECLARE(expires_at)

CAPABILITIES(/datum/ai_intent)
	ref_one(nameof(subject))
	ref_one(nameof(source))

/// The pack falls back from the subject.
/datum/ai_intent/retreat
	name = "retreat"

/// The pack goes to the subject's aid (or against it).
/datum/ai_intent/assist
	name = "assist"

/// The pack gathers on the subject.
/datum/ai_intent/regroup
	name = "regroup"

/datum/ai_pack
	/// The orders in force (live ones are read through active_intents()).
	var/list/intents = null

/// Gives `pack` an order. One per (kind, source, subject): a repeat renews it. Returns the intent.
/proc/intend(datum/ai_pack/pack, intent_type, atom/subject = null, datum/source = null, lasts = 0)
	if(!pack || QDELETED(pack))
		return null
	var/datum/ai_intent/found = null
	for(var/datum/ai_intent/I as anything in pack.intents)
		if(I.type == intent_type && I.source == source && I.subject == subject)
			found = I
			break
	if(!found)
		found = new intent_type
		rel_add(pack, nameof(pack.intents), found)
		rel_set(found, nameof(found.subject), subject)
		rel_set(found, nameof(found.source), source)
	if(lasts)
		EXPIRY_SET(found, expires_at, lasts, CLOCK_WORLD)
	else
		EXPIRY_CLEAR(found, expires_at)
	pack.trace("intent [found.name] on [subject || "nothing"] from [source || "no one"] [lasts ? "for [lasts] ds" : "until released"]")
	return found

/// Ends the orders of `intent_type` given by `source` (every source when null).
/proc/unintend(datum/ai_pack/pack, intent_type, datum/source = null)
	for(var/datum/ai_intent/I as anything in pack?.intents?.Copy())
		if(I.type == intent_type && (isnull(source) || I.source == source))
			rel_remove(pack, nameof(pack.intents), I)
			spent(I)

/// The orders still in force: expired ones and those whose issuer is gone or dead are released first.
/datum/ai_pack/proc/active_intents()
	. = list()
	for(var/datum/ai_intent/I as anything in intents?.Copy())
		var/mob/living/issuer = istype(I.source, /mob/living) ? I.source : null
		var/stale = (I.expires_at && !EXPIRY_ACTIVE(I, expires_at, CLOCK_WORLD)) || !I.source || QDELETED(I.source) || (issuer && issuer.stat >= DEAD)
		if(stale)
			rel_remove(src, nameof(intents), I)
			spent(I)
			continue
		. += I

/// The orders in force on this brain's pack.
/datum/ai_brain/proc/active_intents()
	return pack ? pack.active_intents() : list()

/// An order of `intent_type` in force that somebody else (not this brain's own mob) gave.
/datum/ai_brain/proc/intent_from_others(intent_type)
	for(var/datum/ai_intent/I as anything in active_intents())
		if(I.type == intent_type && I.source != holder)
			return I
	return null

/// The pack rallies against `target`: every other member holds a grudge against them, and the order is on record.
/datum/ai_pack/proc/rally(atom/target, datum/source, lasts = 60 SECONDS)
	intend(src, /datum/ai_intent/assist, target, source, lasts)
	if(!ismob(target))
		return
	for(var/datum/ai_brain/B as anything in members)
		if(B.get_owner() != source && B.get_owner() != target)
			B.add_personal(target, DQ_DISPOSITION_HOSTILE, lasts, "pack rally")
