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
MSG_DEF_SELF(mob_attacks/no_item, "You have nothing to use.")
MSG_DEF_SELF(mob_attacks/no_hands, "You can't pick things up.")

/// Slam damage is the mob's melee damage times this (the charge's impact).
#define MOB_SLAM_MULTIPLIER 2.5

/datum/capability/lib/mob_attacks/entries()
	return list(
		op("melee", inputs(ai()), reach(REACH_ADJACENT), label("Attack"),
			needs(req_capable(), req_conscious(), req_adjacent(), req(CAP_PROC(ready), because = MSG(mob_attacks/cooling))),
			then(CAP_PROC(melee))),
		op("shoot", inputs(ai()), reach(REACH_VIEW), label("Shoot"),
			needs(req_capable(), req_conscious(), req(CAP_PROC(ready), because = MSG(mob_attacks/cooling)), req(CAP_PROC(has_shot), because = MSG(mob_attacks/no_shot))),
			then(CAP_PROC(shoot))),
		// One step to a turf (or toward an atom): every tactic that repositions the mob (approach, flee, kite, juke, wander, follow, home) uses it.
		op("step", inputs(ai()), reach(REACH_ANY), label("Step"),
			needs(req_capable(), req_conscious()),
			then(CAP_PROC(step_one))),
		op("special", inputs(ai()), reach(REACH_ANY), label("Special attack"),
			needs(req_capable(), req_conscious()),
			then(CAP_PROC(special))),
		// A held gun fired at the target (held = the gun).
		op("fire", inputs(ai()), reach(REACH_VIEW), label("Fire"),
			needs(req_capable(), req_conscious(), req(CAP_PROC(ready), because = MSG(mob_attacks/cooling)), req(CAP_PROC(has_gun), because = MSG(mob_attacks/no_item))),
			then(CAP_PROC(fire))),
		// A held grenade primed and thrown at a turf (held = the grenade).
		op("throw", inputs(ai()), reach(REACH_ANY), label("Throw"),
			needs(req_capable(), req_conscious(), req(CAP_PROC(ready), because = MSG(mob_attacks/cooling)), req(CAP_PROC(has_grenade), because = MSG(mob_attacks/no_item))),
			then(CAP_PROC(throw_it))),
		op("pickup", inputs(ai()), reach(REACH_ADJACENT), label("Pick up"),
			needs(req_capable(), req_conscious(), req_adjacent(), req(CAP_PROC(can_pick_up), because = MSG(mob_attacks/no_hands))),
			then(CAP_PROC(pick_up))),
		// The mob's warning cry: the shout is the action (who hears it reacts through their own brain).
		op("alarm", inputs(ai()), reach(REACH_ANY), label("Sound the alarm"),
			needs(req_capable(), req_conscious()),
			then(CAP_PROC(alarm))),
		// A charge: a telegraphed wind-up, then a dash at the target (up to six tiles) that ends in a slam. Cancelled with its actor or its target.
		op("charge", inputs(ai()), reach(REACH_VIEW), label("Charge"),
			needs(req_capable(), req_conscious()),
			wait(MOB_CHARGE_WINDUP, keeps = ALIVE | TARGET_PRESENT),
			then(CAP_PROC(charge))),
		// A charge's impact on an adjacent target: heavy damage and a knock-down.
		op("slam", inputs(ai()), reach(REACH_ADJACENT), label("Slam"),
			needs(req_capable(), req_conscious(), req_adjacent()),
			then(CAP_PROC(slam))))

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

/// The mob steps one tile to the turf target (or toward the atom).
/datum/capability/lib/mob_attacks/proc/step_one(datum/act/op/A)
	var/mob/living/L = A.actor
	var/atom/where = A.target
	if(!istype(L) || !istype(where) || QDELETED(where))
		return OP_FAILED
	step_to(L, where)
	return OP_OK

/// The mob's special attack (ISpecialAttack(): in the stance the brain set).
/datum/capability/lib/mob_attacks/proc/special(datum/act/op/A)
	var/mob/living/L = A.actor
	var/atom/victim = A.target
	if(!istype(L) || !istype(victim) || QDELETED(victim))
		return OP_FAILED
	act_log(A, "special [victim]")
	L.ISpecialAttack(victim)
	return OP_OK

/datum/capability/lib/mob_attacks/proc/has_gun(datum/act/op/A)
	return istype(A.held, /obj/item/gun)

/datum/capability/lib/mob_attacks/proc/has_grenade(datum/act/op/A)
	return istype(A.held, /obj/item/grenade)

/datum/capability/lib/mob_attacks/proc/fire(datum/act/op/A)
	var/mob/living/L = A.actor
	var/obj/item/gun/G = A.held
	var/atom/victim = A.target
	if(!istype(L) || !istype(G) || !istype(victim) || QDELETED(victim))
		return OP_FAILED
	act_log(A, "fire [G] at [victim]")
	G.Fire(victim, L, null, L.Adjacent(victim), FALSE) // pointblank when adjacent
	return OP_OK

/datum/capability/lib/mob_attacks/proc/throw_it(datum/act/op/A)
	var/mob/living/L = A.actor
	var/obj/item/grenade/G = A.held
	var/atom/where = A.target
	if(!istype(L) || !istype(G) || !isturf(where))
		return OP_FAILED
	act_log(A, "throw [G] at [where]")
	L.drop_from_inventory(G)
	G.activate(L)
	G.throw_at(where, 6, 2, L)
	L.setClickCooldown(8)
	return OP_OK

/datum/capability/lib/mob_attacks/proc/can_pick_up(datum/act/op/A)
	var/mob/living/simple_mob/SM = A.actor
	return istype(SM) && SM.has_hands

/datum/capability/lib/mob_attacks/proc/pick_up(datum/act/op/A)
	var/mob/living/L = A.actor
	var/obj/item/I = A.target
	if(!istype(L) || !istype(I) || QDELETED(I))
		return OP_FAILED
	L.put_in_any_hand_if_possible(I)
	return I.loc == L ? OP_OK : OP_FAILED

/datum/capability/lib/mob_attacks/proc/alarm(datum/act/op/A)
	var/mob/living/L = A.actor
	if(!istype(L))
		return OP_FAILED
	act_message(L, null, others = span_warning("%U% sounds an alarm!"))
	return OP_OK

/datum/capability/lib/mob_attacks/proc/slam(datum/act/op/A)
	var/mob/living/simple_mob/SM = A.actor
	var/atom/victim = A.target
	if(!istype(SM) || !istype(victim) || QDELETED(victim))
		return OP_FAILED
	slam_hit(SM, victim)
	return OP_OK

/// The impact: heavy damage and a knock-down.
/datum/capability/lib/mob_attacks/proc/slam_hit(mob/living/simple_mob/SM, atom/victim)
	generic_hit(victim, SM, rand(SM.melee_damage_lower, SM.melee_damage_upper) * MOB_SLAM_MULTIPLIER, "slams into")
	act_message(SM, victim, others = span_danger("%U% slams into %T% with crushing force!"))
	if(isliving(victim))
		var/mob/living/V = victim
		V.apply_effect(2, WEAKEN)

/// The dash after the wind-up: up to six tiles toward the target, stopping on contact; a slam if it got there.
/datum/capability/lib/mob_attacks/proc/charge(datum/act/op/A)
	var/mob/living/simple_mob/SM = A.actor
	var/atom/victim = A.target
	if(!istype(SM) || !istype(victim) || QDELETED(victim))
		return OP_FAILED
	act_log(A, "charge [victim]")
	for(var/i in 1 to 6)
		if(!SM.Adjacent(victim))
			step_to(SM, victim)
		if(SM.Adjacent(victim))
			break
	if(SM.Adjacent(victim))
		slam_hit(SM, victim)
	return OP_OK
