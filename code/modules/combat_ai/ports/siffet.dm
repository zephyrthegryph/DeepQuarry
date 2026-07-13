// Siffet port — restores the evasive frost-weasel AI that lived on the deleted
// /datum/ai_holder/simple_mob/siffet subtype.
//
// The legacy holder was hostile + retaliate, with a post_melee_attack() that
// hopped to a random adjacent tile after every strike (a darting "bite and
// skitter" pattern). The mob's own IIsAlly() override decided WHO it would
// aggress on sight: it only picks fights with things small enough to take
// (mob_size > 10 → too big → left alone unless it attacks first), but anything
// non-/mob/living (objects) is treated as an ally (never attacked).
//
// Modern port: hostile-on-sight is the default for simple_mobs, so it stays on.
// The darting hop reuses the generic /datum/ai_behavior/evasive_juke (built for
// exactly this legacy pattern). retaliate_to_attacker covers the "fight back if
// hit by something too big" case.
//
// The legacy size rule lived on IIsAlly(), but the modern brain ranks targets
// through disposition_to() (faction + ai_attack_on_sight), which doesn't consult
// IIsAlly — so on its own the siffet would aggress everything. A custom target
// selector restores the nuance: on-sight it only picks targets small enough to
// take (mob_size <= 10), but anything that has personally wronged it (a grudge
// from being attacked) is fair game regardless of size.

/mob/living/simple_mob/animal/sif/siffet/get_ai_target_selectors()
	var/static/list/L = list(
		/datum/target_selector/siffet_prey,
		/datum/target_selector/closest,
	)
	return L

/datum/target_selector/siffet_prey
	name = "siffet prey"

/datum/target_selector/siffet_prey/select(datum/ai_brain/brain, list/candidates)
	if(!length(candidates))
		return null
	var/mob/living/owner = brain.get_owner()
	if(!owner)
		return null
	var/list/filtered = list()
	for(var/mob/living/M as anything in candidates)
		// Things that struck us first (explicit personal grudge) are always
		// fair game; otherwise only pick on the small (mob_size <= 10).
		if(brain.check_attacker(M))
			filtered += M
		else if(M.mob_size <= 10)
			filtered += M
	if(!length(filtered))
		return null
	var/datum/target_selector/closest_selector = dq_get_selector(/datum/target_selector/closest)
	return closest_selector.select(brain, filtered)

/mob/living/simple_mob/animal/sif/siffet/get_ai_behaviors()
	var/static/list/L = list(
		/datum/ai_behavior/evasive_juke,
		/datum/ai_behavior/retaliate_to_attacker,
		/datum/ai_behavior/melee_attack,
		/datum/ai_behavior/maul_unconscious,
		/datum/ai_behavior/approach_threat,
		/datum/ai_behavior/threaten,
		/datum/ai_behavior/flee_low_hp,
		/datum/ai_behavior/idle_wander,
		/datum/ai_behavior/idle_speak,
	)
	return L
