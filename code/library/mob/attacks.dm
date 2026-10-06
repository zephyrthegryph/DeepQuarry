// mob_attacks() (doc/rewrite/final_api.html section 11, section 9): a simple mob's own melee swing and innate shot as ops, so the AI that drives the mob
// uses the same requirements and refusals as anything else that acts. Both are AI-only (inputs(ai())): a player-controlled simple mob attacks through
// its click, which keeps its own path (simple_mob.dm), so declaring them gives the click no new target.
//
//   CAPABILITIES(/mob/living/simple_mob, mob_attacks())
//
// "mob_attacks.melee" needs the target adjacent (req_adjacent(): an AI origin is not held to reach()) and is refused while the mob is still on its attack cooldown; its effect is the mob's IAttack() (attack_target() in the stance the
// brain chose). "mob_attacks.shoot" is the mob's innate projectile (IRangedAttack()), refused with no projectile or on cooldown. The combat
// AI's melee_attack and ranged_attack behaviours call them with perform_op(); what they refuse is traced by the brain (trace()).

CAPABILITY_TYPE(mob_attacks, CAP_MOB_ATTACKS, /datum/capability/lib/mob_attacks, key = NONE)

MSG_DEF_SELF(mob_attacks/cooling, "You are not ready to attack again.")
MSG_DEF_SELF(mob_attacks/no_shot, "You have nothing to shoot with.")

/datum/capability/lib/mob_attacks/entries()
	return list(
		op("melee", inputs(ai()), reach(REACH_ADJACENT), label("Attack"),
			needs(req_capable(), req_adjacent(), req(CAP_PROC(ready), because = MSG(mob_attacks/cooling))),
			then(CAP_PROC(melee))),
		op("shoot", inputs(ai()), reach(REACH_VIEW), label("Shoot"),
			needs(req_capable(), req(CAP_PROC(ready), because = MSG(mob_attacks/cooling)), req(CAP_PROC(has_shot), because = MSG(mob_attacks/no_shot))),
			then(CAP_PROC(shoot))))

/// Off the attack cooldown (the one a click sets: checkClickCooldown()).
/datum/capability/lib/mob_attacks/proc/ready(datum/act/op/A)
	var/mob/living/L = A.actor
	return istype(L) && L.checkClickCooldown()

/// The mob has an innate projectile.
/datum/capability/lib/mob_attacks/proc/has_shot(datum/act/op/A)
	var/mob/living/simple_mob/SM = A.actor
	return istype(SM) && !isnull(SM.projectiletype)

/// The swing: the mob's attack in the brain's stance. A target that is gone is a failed op, a miss is still an attack.
/datum/capability/lib/mob_attacks/proc/melee(datum/act/op/A)
	var/mob/living/simple_mob/SM = A.actor
	var/atom/victim = A.target
	if(!istype(SM) || !istype(victim) || QDELETED(victim))
		return OP_FAILED
	act_log(A, "melee [victim]")
	// IAttack() is the brain's way in: the stance is its own choice (set_use_stance()). Its answer is not read: a miss reports as a failure, and
	// a miss is still an attack (the op's reach and cooldown requirements already held).
	SM.IAttack(victim)
	return OP_OK

/// The shot: shoot_target() at the target.
/datum/capability/lib/mob_attacks/proc/shoot(datum/act/op/A)
	var/mob/living/simple_mob/SM = A.actor
	var/atom/victim = A.target
	if(!istype(SM) || !istype(victim) || QDELETED(victim))
		return OP_FAILED
	act_log(A, "shoot [victim]")
	SM.IRangedAttack(victim)
	return OP_OK
