// Tier 2

/mob/living/simple_mob/slime/xenobio/yellow/get_mechanics_info(list/additional_information)
	return ..(list("In addition to being immune to electrical shocks, this slime will fire ranged lightning attacks at \
	enemies if they are at range, inflict shocks upon entities they attack, and generate electricity for their stun \
	attack faster than usual. Insulative or reflective armor can protect from these attacks.") + additional_information)

/mob/living/simple_mob/slime/xenobio/yellow
	desc ="This slime is very conductive, and is known to use electricity as a means of defense moreso than usual for slimes."
	color = "#FFF423"
	slime_color = "yellow"
	coretype = /obj/item/slime_extract/yellow
	melee_damage_lower = 5
	melee_damage_upper = 5
	shock_resist = 1

	projectiletype = /obj/item/projectile/beam/lightning/slime
	projectilesound = SFX_EFFECTS_LIGHTNINGBOLT
	glow_toggle = TRUE
	player_msg = "You have a <b>ranged electric attack</b>. You also <b>shock enemies you attack</b>, and your electric stun attack charges passively.<br>\
	You are also immune to shocking attacks."

	slime_mutation = list(
			/mob/living/simple_mob/slime/xenobio/bluespace,
			/mob/living/simple_mob/slime/xenobio/bluespace,
			/mob/living/simple_mob/slime/xenobio/metal,
			/mob/living/simple_mob/slime/xenobio/orange
		)

/mob/living/simple_mob/slime/xenobio/yellow/apply_melee_effects(atom/A)
	..()
	if(isliving(A))
		var/mob/living/L = A
		L.inflict_shock_damage(is_adult ? 10 : 5)
		to_chat(src, span_danger("You shock \the [L]."))
		to_chat(L, span_danger("You've been shocked by \the [src]!"))

/mob/living/simple_mob/slime/xenobio/yellow/life_special(datum/seq_frame/life/F)
	if(src.stat == CONSCIOUS)
		if(prob(25))
			src.power_charge = between(0, src.power_charge + 1, 10)
	..()
