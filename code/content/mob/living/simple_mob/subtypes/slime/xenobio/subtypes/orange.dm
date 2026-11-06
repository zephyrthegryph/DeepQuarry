/mob/living/simple_mob/slime/xenobio/orange/get_mechanics_info(list/additional_information)
	return ..(list("The slime is immune to burning attacks, and attacks from this slime will burn you, and can ignite you. \
	A firesuit can protect from the burning attacks of this slime.") + additional_information)

/mob/living/simple_mob/slime/xenobio/orange
	desc ="This slime is known to be flammable and can ignite enemies."
	color = "#FFA723"
	slime_color = "orange"
	coretype = /obj/item/slime_extract/orange
	melee_damage_lower = 5
	melee_damage_upper = 5
	heat_resist = 1
	player_msg = "You <b>inflict burning attacks</b>, which causes additional damage, makes the target more flammable, and has a chance to ignite them.<br>\
	You are also immune to burning attacks."

	slime_mutation = list(
			/mob/living/simple_mob/slime/xenobio/dark_purple,
			/mob/living/simple_mob/slime/xenobio/yellow,
			/mob/living/simple_mob/slime/xenobio/red,
			/mob/living/simple_mob/slime/xenobio
		)

/mob/living/simple_mob/slime/xenobio/orange/apply_melee_effects(atom/A)
	..()
	if(isliving(A))
		var/mob/living/L = A
		L.inflict_heat_damage(is_adult ? 10 : 5)
		to_chat(src, span_danger("You burn \the [L]."))
		to_chat(L, span_danger("You've been burned by \the [src]!"))
		L.adjust_fire_stacks(1)
		if(prob(12))
			L.ignite_mob()
