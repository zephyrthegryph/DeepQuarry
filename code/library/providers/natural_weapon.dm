// natural_weapon(weapon, damage, name, recover) (doc/rewrite/final_api.html, section 8 "providers"; section 11 "Providers"; section 16.7): a mob's own attack.
//
//   CAPABILITIES(/mob/living/simple_mob/animal/space/carp, natural_weapon(/datum/natural_weapon/bite, damage = 10))
//
// It gives the mob two things. A provider, provides(AFF_ATTACK, reach = 1), so the mob has something that strikes without being a hand (a carp has no
// species and no hands: its bite is its whole provider set). And one op, "natural_weapon.attack" (an AI behaviour calls it by key, and a player-controlled mob's click on a hostile stance reaches it: clicks()): adjacent, performed by AFF_ATTACK,
// hostile, with a cooldown; the effect is the target's generic attack at `damage`. The op an AI behaviour reaches with perform_intent(owner, target, INTENT_ATTACK) or perform_op(owner, target, "natural_weapon.attack"), so the requirements, the cooldown and the
// messages are shared. key = name: two weapons on one mob (bite and claw) are natural_weapon(.., name = "bite") and natural_weapon(.., name = "claw").

CAPABILITY_TYPE(natural_weapon, CAP_NATURAL_WEAPON, /datum/capability/lib/natural_weapon, key = name, weapon = /datum/natural_weapon, damage = 10, name = null, recover = 2 SECONDS)

MSG_DEF_SELF(natural_weapon/self, "You can't attack yourself.")
MSG_DEF(natural_weapon/attack, "You attack %T%!", "%U% attacks %T%!")

/// What kind of natural weapon a mob has (the `weapon` param): subtype it for a claw, a sting, a slam.
/datum/natural_weapon
	/// The verb in the attack's log line.
	var/verb_text = "attacks"

/datum/natural_weapon/bite
	verb_text = "bites"

/datum/capability/lib/natural_weapon/entries()
	return list(
		provides(AFF_ATTACK, reach = 1, authority = AUTH_PHYSICAL | AUTH_AI),
		op("attack", inputs(ai(), clicks()), reach(REACH_ADJACENT), by(AFF_ATTACK), hostile(), label("Attack"),
			needs(req(CAP_PROC(not_self))),
			cooldown(recover), then(CAP_PROC(strike)), says(MSG(natural_weapon/attack)), logs(LOG_GAME)))

/datum/capability/lib/natural_weapon/proc/not_self(datum/act/op/A)
	return (!isnull(A.target) && A.target != A.actor) ? null : MSG(natural_weapon/self)

/// The strike: the target takes a generic attack at the weapon's damage.
/datum/capability/lib/natural_weapon/proc/strike(datum/act/op/A)
	var/atom/victim = A.target
	if(!istype(victim) || QDELETED(victim))
		return OP_FAILED
	act_log(A, "[weapon] for [damage]")
	victim.receive_generic_attack(A.actor, damage)
	return OP_OK
