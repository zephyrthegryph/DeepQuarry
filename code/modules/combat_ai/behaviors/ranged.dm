// Ranged combat behaviors.

// --- Basic ranged attack (mob's innate projectile) --------------------------
// Mirrors the existing simple_mob shoot_target() path. Used when the mob has
// a projectiletype set on itself (not a held gun).

/datum/ai_behavior/ranged_attack
	name = "ranged attack"
	priority_class = DQ_BEHAVIOR_PRIORITY_NORMAL
	target_kind = DQ_TARGET_MOB
	min_range = 2
	max_range = 7

/datum/ai_behavior/ranged_attack/applicable_to(mob/living/owner)
	if(!istype(owner, /mob/living/simple_mob))
		return FALSE
	var/mob/living/simple_mob/SM = owner
	return SM.projectiletype != null

/datum/ai_behavior/ranged_attack/evaluate(datum/ai_brain/brain, atom/source)
	var/mob/living/owner = brain.get_owner()
	var/mob/threat = brain.primary_threat
	if(!owner || !threat)
		return null
	var/dist = get_dist(owner, threat)
	if(dist < min_range || dist > max_range)
		return null
	if(!owner.checkClickCooldown())
		return null
	// Slightly under melee at adjacency; ties or wins at 3+ tiles.
	var/score = 30 + min(dist * 4, 30)
	return DQAI_RESULT(score, threat)

/datum/ai_behavior/ranged_attack/start(datum/ai_brain/brain, atom/target, atom/source)
	. = ..()
	if(. == DQ_BEHAVIOR_FAILED)
		return
	var/mob/living/simple_mob/SM = brain.get_owner()
	if(!istype(SM))
		return DQ_BEHAVIOR_FAILED
	SM.shoot_target(target)
	brain.last_attack_at = world.time
	return DQ_BEHAVIOR_DONE

// --- Aimed shot (granted by held guns) --------------------------------------
// Item-granted behavior. The gun owns its own cooldown and ammo state; the
// behavior is a stateless adapter that asks the gun if it can fire and tells
// it to.

/datum/ai_behavior/aimed_shot
	name = "aimed shot"
	priority_class = DQ_BEHAVIOR_PRIORITY_NORMAL
	target_kind = DQ_TARGET_MOB
	requires_held_source = TRUE
	min_range = 2
	max_range = 7

/datum/ai_behavior/aimed_shot/evaluate(datum/ai_brain/brain, atom/source)
	if(!istype(source, /obj/item/gun))
		return null
	var/obj/item/gun/G = source
	var/mob/living/owner = brain.get_owner()
	var/mob/threat = brain.primary_threat
	if(!owner || !threat)
		return null
	if(!owner.checkClickCooldown())
		return null
	if(world.time < G.next_fire_time)
		return null
	// Gun-side ammo check via existing special_check (most guns subclass this).
	if(!G.special_check(owner))
		return null
	var/dist = get_dist(owner, threat)
	if(dist < min_range || dist > max_range)
		return null
	// Score higher than innate ranged_attack — held guns are the better tool.
	var/score = 55 + min(dist * 3, 20)
	return DQAI_RESULT(score, threat)

/datum/ai_behavior/aimed_shot/start(datum/ai_brain/brain, atom/target, atom/source)
	. = ..()
	if(. == DQ_BEHAVIOR_FAILED)
		return
	var/mob/living/owner = brain.get_owner()
	var/obj/item/gun/G = source
	if(!owner || !istype(G))
		return DQ_BEHAVIOR_FAILED
	// Use the gun's existing fire pipeline. Pointblank when adjacent.
	var/pointblank = owner.Adjacent(target)
	G.Fire(target, owner, null, pointblank, FALSE)
	brain.last_attack_at = world.time
	return DQ_BEHAVIOR_DONE
