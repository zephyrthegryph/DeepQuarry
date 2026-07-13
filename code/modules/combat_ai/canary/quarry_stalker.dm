// Quarry Stalker — an ambush predator built on the modern AI framework. It does NOT brawl:
// it keeps its distance and circles its prey (stalk_orbit), staying just out of reach, and
// only commits to the kill when the prey is weakened (low HP/stamina, staggered, or downed)
// or alone (no ally nearby). When it commits it pounces in with a telegraphed dash, then
// tears in with melee — and breaks off to circle again if the prey rallies.
//
// Behaviors:
//   - threaten on first sight
//   - stalk_orbit while stalking — hold the band, strafe/circle
//   - stalk_pounce — the telegraphed commit dash (only when prey is weak/alone)
//   - approach + melee + telegraphed heavy once it has closed for the kill
//   - sidestep_dodge — slips the player's telegraphed swings
//   - flee_low_hp under 40% HP
//
// No legacy ai_holder — `use_modern_ai = TRUE`.

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
		/datum/ai_behavior/stalk_orbit,               // keep range + circle while the prey is fresh
		/datum/ai_behavior/charge_slam/stalk_pounce,  // commit dash, only when the prey is weak/alone
		/datum/ai_behavior/approach_threat,           // close the last gap once committed
		/datum/ai_behavior/melee_attack,
		/datum/ai_behavior/telegraphed_strike/flinch, // agile elite: yanks the heavy back to dodge an incoming swing
		/datum/ai_behavior/sidestep_dodge,
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
