// Throw-grenade behavior. Granted by /obj/item/grenade. Picks a turf with the
// most clustered hostiles, primes, throws.

/datum/ai_behavior/throw_grenade
	name = "throw grenade"
	priority_class = DQ_BEHAVIOR_PRIORITY_NORMAL
	target_kind = DQ_TARGET_TURF
	requires_held_source = TRUE
	min_range = 3
	max_range = 6

	/// How many hostiles need to be in a 1-tile radius around the candidate
	/// turf before a grenade is worth using.
	var/min_cluster_size = 2

/datum/ai_behavior/throw_grenade/evaluate(datum/ai_brain/brain, atom/source)
	if(!istype(source, /obj/item/grenade))
		return null
	var/obj/item/grenade/G = source
	if(G.active)  // already primed; don't double-throw
		return null
	var/mob/living/owner = brain.get_owner()
	if(!owner || !brain.model)
		return null
	if(!owner.checkClickCooldown())
		return null

	// Find the turf with the densest hostile cluster.
	var/turf/best_turf
	var/best_count = 0
	for(var/mob/living/M as anything in brain.model.visible_hostiles)
		var/turf/T = get_turf(M)
		if(!T)
			continue
		var/d = get_dist(owner, T)
		if(d < min_range || d > max_range)
			continue
		var/count = 0
		for(var/mob/living/N in range(1, T))
			if(N in brain.model.visible_hostiles)
				count++
		if(count > best_count)
			best_count = count
			best_turf = T

	if(best_count < min_cluster_size || !best_turf)
		return null
	// Higher cluster size → much higher score, biased over plain ranged.
	return DQAI_RESULT(60 + best_count * 15, best_turf)

/datum/ai_behavior/throw_grenade/start(datum/ai_brain/brain, atom/target, atom/source)
	. = ..()
	if(. == DQ_BEHAVIOR_FAILED)
		return
	var/mob/living/owner = brain.get_owner()
	var/obj/item/grenade/G = source
	if(!owner || !istype(G) || !isturf(target))
		return DQ_BEHAVIOR_FAILED
	owner.visible_message(span_warning("[owner] hurls [G]!"))
	// Use the grenade's own activate/throw pipeline. Drop from hand first.
	owner.drop_from_inventory(G)
	G.activate(owner)
	G.throw_at(target, max_range, 2, owner)
	owner.setClickCooldown(8)
	return DQ_BEHAVIOR_DONE

/datum/ai_behavior/throw_grenade/get_player_verb_info()
	// auto_target = TRUE: re-uses evaluate()'s cluster-finder so the player
	// hurls at the densest enemy clump. Manual click-throw is still available.
	var/static/list/L = list(
		"name" = "Throw Grenade (smart)",
		"desc" = "Throw a held grenade at the densest enemy cluster.",
		"category" = "Combat",
		"auto_target" = TRUE,
	)
	return L
