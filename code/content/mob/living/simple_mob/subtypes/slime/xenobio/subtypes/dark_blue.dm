/mob/living/simple_mob/slime/xenobio/dark_blue/get_mechanics_info(list/additional_information)
	return ..(list("This slime is immune to the cold, however water will still kill it. Its presence, as well as its attacks, will \
	also cause you additional harm from the cold. A winter coat or other cold-resistant clothing can protect from this.") + additional_information)

/mob/living/simple_mob/slime/xenobio/dark_blue
	desc ="This slime makes other entities near it feel much colder, and is more resilient to the cold.  It tends to kill other slimes rather quickly."
	color = "#2398FF"
	glow_toggle = TRUE
	slime_color = "dark blue"
	coretype = /obj/item/slime_extract/dark_blue
	melee_damage_lower = 5
	melee_damage_upper = 5
	cold_resist = 1
	player_msg = "You are <b>immune to the cold</b>, inflict additional cold damage on attack, and cause nearby entities to suffer from coldness."

	slime_mutation = list(
			/mob/living/simple_mob/slime/xenobio/purple,
			/mob/living/simple_mob/slime/xenobio/blue,
			/mob/living/simple_mob/slime/xenobio/cerulean,
			/mob/living/simple_mob/slime/xenobio/cerulean
		)

	minbodytemp = 0
	cold_damage_per_tick = 0

/mob/living/simple_mob/slime/xenobio/dark_blue/life_special(datum/seq_frame/life/F)
	if(src.stat != DEAD)
		src.cold_aura()
	..()

/mob/living/simple_mob/slime/xenobio/dark_blue/proc/cold_aura()
	for(var/mob/living/L in view(2, src))
		if(L == src)
			continue
		chill(L)

	var/turf/T = get_turf(src)
	var/datum/gas_mixture/env = T.return_air()
	if(env)
		heat_add(env, -10 * 1000, HEAT_SOURCE_OTHER)

/mob/living/simple_mob/slime/xenobio/dark_blue/apply_melee_effects(atom/A)
	..()
	if(isliving(A))
		var/mob/living/L = A
		chill(L)
		to_chat(src, span_danger("You chill \the [L]."))
		to_chat(L, span_danger("You've been chilled by \the [src]!"))

/mob/living/simple_mob/slime/xenobio/dark_blue/proc/chill(mob/living/L)
	L.inflict_cold_damage(is_adult ? 10 : 5)
	if(L.get_cold_protection() < 1 && (L.ai_brain != null)) // Harmful auras will make the AI react to its bearer.
		L.ai_brain.react_to_attack(src)
