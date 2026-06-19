// Tactical / movement-modifier behaviors.
//
// These behaviors take advantage of the brain's A* pathing and the
// post-attack / damage-event signal hooks to give each archetype the texture
// of its legacy AI subtype (kiting, hit-and-run, evasive juke, etc).
// All are opt-in: mobs that want them list them in get_ai_behaviors().

// --- Evasive juke ----------------------------------------------------------
// Step into an adjacent random cardinal after each completed melee attack.
// Used by /datum/ai_holder/simple_mob/melee/evasive in the legacy system.
// Triggered on the damage-taken-by-attacker signal — see start().

/datum/ai_behavior/evasive_juke
	name = "juke"
	priority_class = DQ_BEHAVIOR_PRIORITY_INTERRUPT
	target_kind = DQ_TARGET_MOB
	cooldown = 0
	// Fires every fast tick once primary_threat exists; the score gating
	// keeps it from running unless we just attacked.
	eval_triggers = list(COMSIG_DQAI_TARGET_CHANGED)

/datum/ai_behavior/evasive_juke/evaluate(datum/ai_brain/brain, atom/source)
	// Only relevant immediately after a melee strike.
	if(!brain.primary_threat)
		return null
	if(!brain.last_attack_at || world.time > brain.last_attack_at + 4)
		return null
	if(brain.last_juke_at == brain.last_attack_at)
		return null
	var/mob/living/owner = brain.get_owner()
	if(!owner.Adjacent(brain.primary_threat))
		return null
	return DQAI_RESULT(70, brain.primary_threat)

/datum/ai_behavior/evasive_juke/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/owner = brain.get_owner()
	if(!owner)
		return DQ_BEHAVIOR_FAILED
	brain.last_juke_at = brain.last_attack_at
	var/turf/T = get_step(owner, pick(GLOB.alldirs))
	if(T && !T.density)
		step_to(owner, T)
	owner.face_atom(target)
	return DQ_BEHAVIOR_DONE

// --- Kiting ----------------------------------------------------------------
// After firing a ranged attack, back away if the target is too close. Mirrors
// /datum/ai_holder/simple_mob/ranged/kiting.

/datum/ai_behavior/kite_away
	name = "kite"
	priority_class = DQ_BEHAVIOR_PRIORITY_INTERRUPT
	target_kind = DQ_TARGET_MOB
	eval_triggers = list(COMSIG_DQAI_TARGET_CHANGED)
	/// Tile distance below which we want to back off.
	var/kite_distance = 4

/datum/ai_behavior/kite_away/evaluate(datum/ai_brain/brain, atom/source)
#if DQ_AI_RETREAT_DISABLED
	return null // no kiting — close in and stay in
#else
	var/mob/threat = brain.primary_threat
	if(!threat)
		return null
	var/mob/living/owner = brain.get_owner()
	if(!owner)
		return null
	var/dist = get_dist(owner, threat)
	if(dist >= kite_distance)
		return null
	// Only kite if we have ranged ability.
	if(istype(owner, /mob/living/simple_mob))
		var/mob/living/simple_mob/SM = owner
		if(!SM.projectiletype)
			return null
	return DQAI_RESULT(65, threat)
#endif

/datum/ai_behavior/kite_away/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/owner = brain.get_owner()
	if(!owner || !target)
		return DQ_BEHAVIOR_FAILED
	var/turf/away = get_step_away(owner, target, kite_distance)
	if(away && !away.density)
		dq_ai_step_to(owner, away) // throttled to the AI move pace
	owner.face_atom(target)
	return DQ_BEHAVIOR_DONE

// --- Hit-and-run -----------------------------------------------------------
// After an attack, flee briefly if uncloaked and target isn't stunned.
// Mirrors /datum/ai_holder/simple_mob/melee/hit_and_run.

/datum/ai_behavior/hit_and_run
	name = "hit and run"
	priority_class = DQ_BEHAVIOR_PRIORITY_INTERRUPT
	target_kind = DQ_TARGET_MOB
	eval_triggers = list(COMSIG_DQAI_TARGET_CHANGED)
	cooldown = 5 SECONDS

/datum/ai_behavior/hit_and_run/evaluate(datum/ai_brain/brain, atom/source)
#if DQ_AI_RETREAT_DISABLED
	return null // no darting away after a hit
#else
	var/mob/threat = brain.primary_threat
	if(!threat || !ismob(threat))
		return null
	if(!brain.last_attack_at || world.time > brain.last_attack_at + 6)
		return null
	var/mob/living/owner = brain.get_owner()
	if(!owner)
		return null
	if(owner.is_cloaked())
		return null  // safe, don't flee
	if(isliving(threat))
		var/mob/living/L = threat
		if(L.incapacitated(INCAPACITATION_DISABLED))
			return null  // target is stunned; keep attacking
	return DQAI_RESULT(75, threat)
#endif

/datum/ai_behavior/hit_and_run/start(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/owner = brain.get_owner()
	if(!owner || !target)
		return DQ_BEHAVIOR_FAILED
	var/turf/away = get_step_away(owner, target)
	if(away && !away.density)
		dq_ai_step_to(owner, away) // throttled to the AI move pace
	return DQ_BEHAVIOR_CONTINUE

/datum/ai_behavior/hit_and_run/tick(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/owner = brain.get_owner()
	if(!owner || !target)
		return DQ_BEHAVIOR_FAILED
	if(get_dist(owner, target) >= 5)
		return DQ_BEHAVIOR_DONE
	var/turf/away = get_step_away(owner, target)
	if(away && !away.density)
		dq_ai_step_to(owner, away) // throttled to the AI move pace
	return DQ_BEHAVIOR_CONTINUE

// --- Pack flee (on dying / outmatched) -------------------------------------
// Pack predators retreat when overmatched or near death. Mirrors
// /datum/ai_holder/simple_mob/melee/pack_mob's flee_when_dying / outmatched.

/datum/ai_behavior/pack_retreat
	name = "pack retreat"
	priority_class = DQ_BEHAVIOR_PRIORITY_INTERRUPT
	target_kind = DQ_TARGET_MOB
	eval_triggers = list(COMSIG_DQAI_LOW_HEALTH, COMSIG_DQAI_DAMAGE_TAKEN)
	cooldown = 3 SECONDS

/datum/ai_behavior/pack_retreat/evaluate(datum/ai_brain/brain, atom/source)
#if DQ_AI_RETREAT_DISABLED
	return null // packs don't fall back — they commit
#else
	var/mob/living/owner = brain.get_owner()
	var/mob/threat = brain.primary_threat
	if(!owner || !threat || !owner.maxHealth)
		return null
	var/dying = owner.health / owner.maxHealth < 0.3
	// "Outmatched" — genuinely alone (no pack), not merely unable to SEE allies. A pack
	// that spreads out to flank loses line of sight to its own members, so reading
	// visible_friendlies made the whole pack think it was solo and flee at once. The lord
	// is the real source of truth for "do I have backup", so trust it.
	var/no_backup = !brain.lord || length(brain.lord.members) <= 1
	var/outmatched = FALSE
	if(no_backup && isliving(threat))
		var/mob/living/threat_living = threat
		outmatched = threat_living.health > owner.health
	if(!dying && !outmatched)
		return null
	return DQAI_RESULT(120, threat)  // overrides plain flee_low_hp
#endif

/datum/ai_behavior/pack_retreat/tick(datum/ai_brain/brain, atom/target, atom/source)
	var/mob/living/owner = brain.get_owner()
	if(!owner || !target)
		return DQ_BEHAVIOR_FAILED
	if(get_dist(owner, target) >= 10)
		return DQ_BEHAVIOR_DONE
	var/turf/away = get_step_away(owner, target)
	if(away && !away.density)
		dq_ai_step_to(owner, away) // throttled to the AI move pace
	return DQ_BEHAVIOR_CONTINUE

// --- Return home -----------------------------------------------------------
// Guard-mob walks back to its spawn turf when idle and far from it. Mirrors
// /datum/ai_holder.returns_home semantics.

/datum/ai_behavior/return_home
	name = "return home"
	priority_class = DQ_BEHAVIOR_PRIORITY_IDLE
	target_kind = DQ_TARGET_TURF
	no_threat_required = TRUE
	/// How far from home triggers a return.
	var/return_threshold = 5

/datum/ai_behavior/return_home/evaluate(datum/ai_brain/brain, atom/source)
	if(brain.primary_threat)
		return null  // in combat, don't run home
	var/mob/living/owner = brain.get_owner()
	var/turf/home = brain.home_turf
	if(!owner || !home)
		return null
	var/turf/owner_turf = get_turf(owner) // get_turf, not owner.z: a contained mob reports z 0
	if(!owner_turf || owner_turf.z != home.z)
		return null
	// Use brain.max_home_distance as override when set; defaults to return_threshold.
	var/threshold = brain.max_home_distance || return_threshold
	if(get_dist(owner, home) < threshold)
		return null
	return DQAI_RESULT(8, home)

/datum/ai_behavior/return_home/tick(datum/ai_brain/brain, atom/target, atom/source)
	if(!target || !brain.holder)
		return DQ_BEHAVIOR_FAILED
	if(brain.smart_step_toward(target, 0))
		if(get_dist(brain.holder, target) == 0)
			return DQ_BEHAVIOR_DONE
		return DQ_BEHAVIOR_CONTINUE
	return DQ_BEHAVIOR_CONTINUE

// --- Follow leader ---------------------------------------------------------
// Cooperative AI follows the brain.leader weakref when not in combat. Used
// for /datum/ai_holder/simple_mob/passive pets and pack-mob fledglings.

/datum/ai_behavior/follow_leader
	name = "follow leader"
	priority_class = DQ_BEHAVIOR_PRIORITY_IDLE
	target_kind = DQ_TARGET_MOB
	no_threat_required = TRUE
	var/follow_distance = 2

/datum/ai_behavior/follow_leader/evaluate(datum/ai_brain/brain, atom/source)
	if(brain.primary_threat)
		return null
	var/mob/leader = brain.get_leader()
	if(!leader)
		return null
	var/mob/living/owner = brain.get_owner()
	if(!owner)
		return null
	// get_turf both sides: either the follower or the leader could be inside a
	// container (a contained mob's .z is 0, which would falsely read cross-z).
	var/turf/owner_turf = get_turf(owner)
	var/turf/leader_turf = get_turf(leader)
	if(!owner_turf || !leader_turf || owner_turf.z != leader_turf.z)
		return null
	if(get_dist(owner, leader) <= follow_distance)
		return null
	return DQAI_RESULT(15, leader)

/datum/ai_behavior/follow_leader/tick(datum/ai_brain/brain, atom/target, atom/source)
	if(!target || !brain.holder)
		return DQ_BEHAVIOR_FAILED
	if(get_dist(brain.holder, target) <= follow_distance)
		return DQ_BEHAVIOR_DONE
	brain.smart_step_toward(target, follow_distance)
	return DQ_BEHAVIOR_CONTINUE
