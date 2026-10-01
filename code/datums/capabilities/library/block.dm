// cap_block(): the held or worn item stops hits outright (named cap_block() because DM reserves block()).
// It answers the existing shield step (/mob/living/proc/check_shields() -> handle_shield()): the base
// /obj/item/proc/handle_shield() asks the item's block capability, so a type that overrides
// handle_shield() keeps its own rules.
//
//	/obj/item/material/twohanded/capabilities()
//		. = ..()
//		. += cap_block(chance = 15, needs_wielded = TRUE, verb = "parries")

/datum/capability/block
	works_broken = TRUE
	works_unpowered = TRUE
	/// Percent chance to stop a hit it can reach.
	var/chance = 50
	/// Projectiles too (a shield), not only melee from an adjacent attacker (a parry).
	var/projectiles = FALSE
	/// Only while held in both hands (cap_two_handed()).
	var/needs_wielded = FALSE
	/// The verb in the block message: "%U% blocks the attack with %T%!".
	var/verb = "blocks"

/proc/cap_block(chance = 50, projectiles = FALSE, needs_wielded = FALSE, verb = "blocks", needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log)
	var/datum/capability/block/C = new
	C.chance = clamp(chance, 0, 100)
	C.projectiles = projectiles
	C.needs_wielded = needs_wielded
	C.verb = verb
	cap_gating(C, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)
	return C

/// Whether the block could stop this hit at all (before the roll): not from behind, and the right
/// kind of hit. Pure.
/datum/capability/block/proc/can_block(obj/item/holder, mob/user, atom/damage_source, mob/attacker)
	if(!user || user.incapacitated())
		return FALSE
	if(needs_wielded && !cap_has(holder, CAP_WIELDED))
		return FALSE
	if(!projectiles)
		return default_parry_check(user, attacker, damage_source)
	return check_shield_arc(user, reverse_direction(user.dir), damage_source, attacker)

/datum/capability/block/examine(atom/holder, mob/user)
	var/what = projectiles ? "blows and shots" : "blows"
	if(needs_wielded)
		return list("Held in both hands, it can turn aside [what].")
	return list("It can turn aside [what].")

/// The shield step for items with a block capability: TRUE when it stopped the hit.
/obj/item/proc/cap_block_hit(mob/user, damage, atom/damage_source, mob/attacker, attack_text = "the attack")
	var/datum/capability/block/C = cap_of(src, /datum/capability/block)
	if(!C || !C.can_block(src, user, damage_source, attacker))
		return FALSE
	if(!prob(C.chance))
		return FALSE
	act_message(user, src, others = span_danger("%U% [C.verb] [attack_text] with %T%!"))
	return TRUE
