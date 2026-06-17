// Default behavior factory.
//
// When a mob declares use_modern_ai = TRUE but doesn't override
// get_ai_behaviors(), the brain composes a sensible default list from the
// mob's stats (melee_damage, projectiletype, has_hands) and its
// ai_attack_on_sight flag. This lets us migrate every simple_mob to the new
// framework by flipping one flag, without hand-editing each subtype.
//
// Each default list is a single proc-local static — instantiated once on
// first use, shared across every mob in the round whose stats match.

GLOBAL_LIST_EMPTY(dq_default_behavior_cache)

/// Compose a default behavior list for the given mob. Returns a per-shape
/// static list (cached by signature) so identical-shape mobs share storage.
/proc/dq_default_behavior_list_for(mob/living/simple_mob/SM)
	if(!istype(SM))
		return null
	// Compose a signature from the mob's combat shape.
	var/has_melee = SM.melee_damage_upper > 0
	var/has_ranged = SM.projectiletype != null
	var/has_hands  = SM.has_hands
	var/hostile    = SM.ai_attack_on_sight
	var/vore       = SM.vore_active
	var/sig = "[has_melee][has_ranged][has_hands][hostile][vore]"

	var/list/cached = GLOB.dq_default_behavior_cache[sig]
	if(cached)
		return cached

	var/list/L = list()
	// Idle always.
	L += /datum/ai_behavior/idle_wander
	L += /datum/ai_behavior/idle_speak
	// Curiosity — walk over and check out a loud nearby noise when not fighting.
	L += /datum/ai_behavior/investigate_noise
	// Destination walking — every mob can be given a target turf to head to
	// (used by migration events, technomancer control, admin tools).
	L += /datum/ai_behavior/walk_to_destination

	// Retaliation works for any mob that can fight back.
	if(has_melee || has_ranged)
		L += /datum/ai_behavior/retaliate_to_attacker

	if(hostile)
		// On-sight aggressors get the full kit. (No call_for_help: the AI lord already
		// coordinates pack aggro, so the "sounds an alarm" bark was just noise.)
		L += /datum/ai_behavior/threaten
		L += /datum/ai_behavior/approach_threat
		L += /datum/ai_behavior/flee_low_hp

	if(has_melee)
		L += /datum/ai_behavior/melee_attack
		L += /datum/ai_behavior/telegraphed_strike // readable heavy + punish opening
		if(hostile)
			L += /datum/ai_behavior/sidestep_dodge   // dodge the player's telegraphed swing
			L += /datum/ai_behavior/brace_guard       // fallback when there's no room to dodge
			L += /datum/ai_behavior/back_off          // give ground after taking a hit
			L += /datum/ai_behavior/maul_unconscious
			// A vore-capable predator devours through the telegraphed grapple sequence
			// (tackle -> pin -> reinforce -> swallow), gated on the prey being worn down —
			// NOT the old instant pounce/bump-swallow. Without this in the kit, AI vore
			// mobs can only melee (the auto-eat paths are disabled for AI).
			if(vore)
				L += /datum/ai_behavior/predation

	if(has_ranged)
		L += /datum/ai_behavior/ranged_attack

	if(has_hands)
		L += /datum/ai_behavior/scavenge_weapon

	GLOB.dq_default_behavior_cache[sig] = L
	return L
