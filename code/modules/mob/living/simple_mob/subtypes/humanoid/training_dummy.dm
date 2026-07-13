// Practice targets for the melee system. Both are unkillable (godmode element) so they stay up
// however long you train on them, and both are anchored so a hit doesn't shove them around.
//
//  - The base dummy has no AI at all: it just stands there and takes hits, for drilling swings,
//    combos and the floor-swipe.
//  - The /aggressive subtype keeps a normal combat brain but is given ONLY the melee_attack
//    behavior (no approach_threat, no idle_wander), so it strikes back when you stand next to it
//    yet never chases — ideal for practising blocks, parries and feints against live attacks.

/mob/living/simple_mob/humanoid/training_dummy
	name = "training dummy"
	desc = "A padded practice dummy, bolted to the floor. It doesn't fight back."
	icon = 'icons/mob/mercenaries.dmi'
	icon_state = "syndicate"
	icon_living = "syndicate"
	icon_dead = "syndicate_dead"
	color = "#9fb8d6" // calm blue-grey: the safe one
	anchored = TRUE
	use_modern_ai = FALSE // no brain — never acts
	melee_damage_lower = 0
	melee_damage_upper = 0
	corpse = null
	loot_list = null
	can_be_drop_prey = FALSE

/mob/living/simple_mob/humanoid/training_dummy/Initialize(mapload)
	. = ..()
	AddElement(/datum/element/godmode) // unkillable: takes hits but never goes down

/mob/living/simple_mob/humanoid/training_dummy/aggressive
	name = "sparring dummy"
	desc = "A combat drone bolted to the floor. It strikes back at anyone in reach, but cannot give chase."
	color = "#d67f7f" // red: this one hits back
	faction = FACTION_SYNDICATE // hostile to players so the brain engages
	use_modern_ai = TRUE
	melee_damage_lower = 8
	melee_damage_upper = 12
	attacktext = list("strikes", "jabs", "clubs")

/mob/living/simple_mob/humanoid/training_dummy/aggressive/get_ai_behaviors()
	// No movement behaviors, so it never chases — but it pokes (melee_attack) and winds up readable
	// heavies (telegraphed_strike) to practise parry / dodge / block and punishing its openings.
	var/static/list/L = list(
		/datum/ai_behavior/melee_attack,
		/datum/ai_behavior/telegraphed_strike,
	)
	return L
