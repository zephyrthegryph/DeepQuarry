// Bridges incoming damage into the brain's notify pipeline.
//
// We re-open apply_damage instead of editing it, so the brain learns of every
// hit regardless of the source (projectile, melee, environmental). Cost when
// the mob has no brain: one TRUE/FALSE check.

/mob/living/apply_damage(damage = 0, damagetype = BRUTE, def_zone = null, blocked = 0, sharp = FALSE, edge = FALSE, used_weapon = null, projectile = null)
	. = ..()
	if(!ai_brain || damage <= 0)
		return
	var/atom/attacker = null
	if(istype(used_weapon, /atom))
		var/atom/weapon = used_weapon
		// If a mob is wielding the weapon, treat them as the attacker.
		if(ismob(weapon.loc))
			attacker = weapon.loc
		else
			attacker = weapon
	if(istype(projectile, /obj/item/projectile))
		var/obj/item/projectile/P = projectile
		if(P.firer)
			attacker = P.firer
	dq_notify_damage(damage, damagetype, attacker)

// Generic-attack path used by simple_mob -> simple_mob fights.
/mob/living/attack_generic(mob/user, damage, attack_message)
	. = ..()
	if(ai_brain && damage > 0)
		dq_notify_damage(damage, BRUTE, user)
