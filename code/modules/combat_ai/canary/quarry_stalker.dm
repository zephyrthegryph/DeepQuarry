// Quarry Stalker — canary mob proving the modern AI framework works end-to-end.
//
// Behaviors:
//   - threaten on first sight
//   - approach when out of range
//   - melee_attack when adjacent
//   - charge_slam at 3-6 tiles (the showpiece — telegraphed dash)
//   - flee_low_hp under 40% HP
//   - idle_wander when nothing to do
//
// No legacy ai_holder — `use_modern_ai = TRUE`, `ai_holder_type = null`.
// Compare against any vanilla hostile simple_mob to see the difference: this
// mob announces itself, telegraphs the dash, and retreats when wounded.

/mob/living/simple_mob/quarry_stalker
	name = "quarry stalker"
	desc = "A lithe predator with too many legs, eyes set deep in armoured plates. It watches before it moves."
	icon = 'icons/mob/animal.dmi'           // placeholder; swap when art lands
	icon_state = "tiger"
	icon_living = "tiger"
	icon_dead = "tiger-dead"

	faction = FACTION_CREATURE
	maxHealth = 90
	health = 90

	melee_damage_lower = 8
	melee_damage_upper = 14
	attacktext = list("bites", "rakes", "tears at")
	attack_sound = 'sound/weapons/bite.ogg'
	base_attack_cooldown = 1.2 SECONDS

	movement_cooldown = 2
	has_hands = FALSE

	can_pain_emote = FALSE
	use_modern_ai = TRUE

/mob/living/simple_mob/quarry_stalker/get_ai_behaviors()
	var/static/list/L = list(
		/datum/ai_behavior/retaliate_to_attacker,
		/datum/ai_behavior/threaten,
		/datum/ai_behavior/approach_threat,
		/datum/ai_behavior/melee_attack,
		/datum/ai_behavior/telegraphed_strike/flinch, // agile elite: yanks the heavy back to dodge an incoming swing
		/datum/ai_behavior/sidestep_dodge,
		/datum/ai_behavior/charge_slam,
		/datum/ai_behavior/flee_low_hp,
		/datum/ai_behavior/idle_wander,
	)
	return L

/mob/living/simple_mob/quarry_stalker/get_ai_target_selectors()
	var/static/list/L = list(
		/datum/target_selector/prefer_players,
		/datum/target_selector/closest,
	)
	return L
