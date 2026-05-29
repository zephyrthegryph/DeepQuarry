// Concrete target selectors.

/// Closest hostile by tile distance. The default for most mobs.
/datum/target_selector/closest
	name = "closest"

/datum/target_selector/closest/select(datum/ai_brain/brain, list/candidates)
	if(!length(candidates))
		return null
	var/mob/living/owner = brain.get_owner()
	if(!owner)
		return null
	var/best
	var/best_dist = INFINITY
	for(var/mob/M as anything in candidates)
		var/d = get_dist(owner, M)
		if(d < best_dist)
			best_dist = d
			best = M
	return best

/// Lowest absolute HP. Pack predators, finishers.
/datum/target_selector/lowest_hp
	name = "lowest hp"

/datum/target_selector/lowest_hp/select(datum/ai_brain/brain, list/candidates)
	var/best
	var/best_hp = INFINITY
	for(var/mob/living/M as anything in candidates)
		if(M.health < best_hp)
			best_hp = M.health
			best = M
	return best

/// Prefer the mob who attacked us most recently. Falls back to closest.
/datum/target_selector/recent_attacker
	name = "recent attacker"

/datum/target_selector/recent_attacker/select(datum/ai_brain/brain, list/candidates)
	if(!length(candidates))
		return null
	var/atom/attacker = brain.model?.get_last_attacker()
	if(attacker && (attacker in candidates))
		return attacker
	return dq_get_selector(/datum/target_selector/closest).select(brain, candidates)

/// Prefer client-controlled mobs over NPCs. For aggressive boss-style mobs.
/datum/target_selector/prefer_players
	name = "prefer players"

/datum/target_selector/prefer_players/select(datum/ai_brain/brain, list/candidates)
	if(!length(candidates))
		return null
	var/list/players = list()
	for(var/mob/living/M as anything in candidates)
		if(M.client)
			players += M
	if(length(players))
		return dq_get_selector(/datum/target_selector/closest).select(brain, players)
	return dq_get_selector(/datum/target_selector/closest).select(brain, candidates)

/// Highest threat — scores by held items granting behaviors + max HP. Cheap
/// approximation, but enough to make mobs target the armed/dangerous first.
/datum/target_selector/highest_threat
	name = "highest threat"

/datum/target_selector/highest_threat/select(datum/ai_brain/brain, list/candidates)
	if(!length(candidates))
		return null
	var/best
	var/best_score = -INFINITY
	for(var/mob/living/M as anything in candidates)
		var/score = M.maxHealth
		// Personal grudges amplify.
		if(brain.disposition_to(M) == DQ_DISPOSITION_NEMESIS)
			score *= 2
		// Held items that grant AI behaviors are dangerous.
		for(var/obj/item/I in M.get_all_held_items())
			var/list/granted = I.get_dq_granted_behaviors()
			if(LAZYLEN(granted))
				score += length(granted) * 25
		if(score > best_score)
			best_score = score
			best = M
	return best
