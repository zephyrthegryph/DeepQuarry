// Melee combat behaviors.

// --- Basic melee attack -----------------------------------------------------
// Standard adjacent strike using the simple_mob's melee_damage_lower/upper
// values via the existing attack_target proc. Delegates to the existing
// combat code so animations, hit sounds, modifiers all keep working.

/datum/ai_behavior/melee_attack
	name = "melee attack"
	priority_class = DQ_BEHAVIOR_PRIORITY_NORMAL
	target_kind = DQ_TARGET_MOB
	min_range = 0
	max_range = 1

/datum/ai_behavior/melee_attack/applicable_to(mob/living/owner)
	if(!istype(owner, /mob/living/simple_mob))
		return FALSE
	var/mob/living/simple_mob/SM = owner
	return SM.melee_damage_upper > 0

/datum/ai_behavior/melee_attack/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/owner = brain.get_owner()
	var/mob/threat = brain.primary_threat
	if(!owner || !threat)
		return null
	if(!owner.Adjacent(threat))
		return null
	if(!owner.checkClickCooldown())
		return null
	// Mid-band score; charge_slam/web_spit beat plain melee when in their range.
	return DQAI_RESULT(40, threat)

/datum/ai_behavior/melee_attack/start(datum/ai_brain/brain, atom/target, atom/source)
	. = ..()
	if(. == DQ_BEHAVIOR_FAILED)
		return
	var/mob/living/simple_mob/SM = brain.get_owner()
	if(!istype(SM))
		return DQ_BEHAVIOR_FAILED
	SM.attack_target(target)
	brain.last_attack_at = world.time
	return DQ_BEHAVIOR_DONE  // single-tick action; attack_target handles cooldown

// --- Charge slam ------------------------------------------------------------
// Telegraphed mid-range gap-closer. Mob freezes, plays a windup, then dashes
// to the target tile, dealing bonus damage on impact. Player-readable.

/datum/ai_behavior/charge_slam
	name = "charge slam"
	desc = "A telegraphed dash that deals heavy damage on impact."
	priority_class = DQ_BEHAVIOR_PRIORITY_OVERRIDE
	target_kind = DQ_TARGET_MOB
	min_range = 3
	max_range = 6
	cooldown = 12 SECONDS
	blocks_reselection = TRUE

	/// Pixel-shake/visible warning duration before the dash fires.
	var/windup = 1.2 SECONDS

	/// Damage multiplier vs the mob's normal melee damage.
	var/damage_mult = 2.5

/datum/ai_behavior/charge_slam/applicable_to(mob/living/owner)
	if(!istype(owner, /mob/living/simple_mob))
		return FALSE
	var/mob/living/simple_mob/SM = owner
	return SM.melee_damage_upper > 0

/datum/ai_behavior/charge_slam/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/owner = brain.get_owner()
	var/mob/threat = brain.primary_threat
	if(!owner || !threat)
		return null
	var/dist = get_dist(owner, threat)
	if(dist < min_range || dist > max_range)
		return null
	// Score high — this is the showpiece. Decays slightly with distance.
	return DQAI_RESULT(80 - dist * 2, threat)

/datum/ai_behavior/charge_slam/start(datum/ai_brain/brain, atom/target, atom/source)
	. = ..()
	if(. == DQ_BEHAVIOR_FAILED)
		return
	var/mob/living/owner = brain.get_owner()
	owner.visible_message(
		span_danger("[owner] crouches, focused on [target]!"),
		blind_message = span_warning("You hear something heavy shift its weight."),
	)
	// This datum is a flyweight singleton shared by every charging mob, so the
	// windup timer can't live on `src`. Stash its id in the brain's per-behavior
	// state and cancel it in stop() if the telegraph gets interrupted.
	LAZYINITLIST(brain.behavior_state)
	if(!brain.behavior_state[type])
		brain.behavior_state[type] = list("cooldown" = 0, "charges" = null)
	brain.behavior_state[type]["dash_timer"] = addtimer(CALLBACK(src, PROC_REF(execute_dash), brain, target), windup, TIMER_STOPPABLE)
	return DQ_BEHAVIOR_CONTINUE

/datum/ai_behavior/charge_slam/stop(datum/ai_brain/brain, atom/target, atom/source, reason)
	// Cancel any pending dash so a cancelled telegraph can't still land.
	if(!QDELETED(brain))
		var/list/state = LAZYACCESS(brain.behavior_state, type)
		if(state && state["dash_timer"])
			deltimer(state["dash_timer"])
			state["dash_timer"] = null
	return ..()

/datum/ai_behavior/charge_slam/proc/execute_dash(datum/ai_brain/brain, atom/target)
	// The 1.2s windup means the brain/holder/target can be gone by the time
	// this fires. Guard each ref before touching it; only call stop_active on
	// a still-live brain.
	if(QDELETED(brain))
		return
	// Confirm this telegraph is still the brain's committed behavior — a
	// cancelled/superseded charge must not deal damage even if its timer leaked.
	if(brain.active_behavior_type != type)
		return
	var/list/state = LAZYACCESS(brain.behavior_state, type)
	if(state)
		state["dash_timer"] = null
	if(QDELETED(brain.holder))
		brain.stop_active(DQ_BEHAVIOR_STOP_FAILED)
		return
	var/mob/living/simple_mob/SM = brain.holder
	if(!istype(SM) || QDELETED(target))
		brain.stop_active(DQ_BEHAVIOR_STOP_FAILED)
		return
	// Step toward the target up to 6 tiles; stop at the first blocker or on contact.
	for(var/i in 1 to 6)
		if(!SM.Adjacent(target))
			step_towards(SM, target)
		if(SM.Adjacent(target))
			break
	if(SM.Adjacent(target))
		var/dmg = rand(SM.melee_damage_lower, SM.melee_damage_upper) * damage_mult
		target.attack_generic(SM, dmg, "slams into")
		SM.visible_message(span_danger("[SM] slams into [target] with crushing force!"))
		if(isliving(target))
			var/mob/living/L = target
			L.apply_effect(2, WEAKEN)
	brain.stop_active(DQ_BEHAVIOR_STOP_COMPLETED)

/datum/ai_behavior/charge_slam/get_player_verb_info()
	var/static/list/L = list(
		"name" = "Charge Slam",
		"desc" = "Crouch, then dash at a target for heavy damage.",
		"category" = "Combat",
		"auto_target" = FALSE,
	)
	return L
