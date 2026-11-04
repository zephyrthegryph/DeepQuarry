/mob/living/simple_mob/slime/xenobio/pink/get_mechanics_info(list/additional_information)
	return ..(list("This slime will passively heal nearby entities within two tiles, including itself. It will only do this while alive.") + additional_information)

/mob/living/simple_mob/slime/xenobio/pink
	desc ="This slime has regenerative properties."
	color = "#FF0080"
	slime_color = "pink"
	coretype = /obj/item/slime_extract/pink
	glow_toggle = TRUE
	player_msg = "You <b>passively heal yourself and nearby allies</b>."

	slime_mutation = list(
			/mob/living/simple_mob/slime/xenobio/blue,
			/mob/living/simple_mob/slime/xenobio/light_pink,
			/mob/living/simple_mob/slime/xenobio/light_pink,
			/mob/living/simple_mob/slime/xenobio/pink
		)

/mob/living/simple_mob/slime/xenobio/pink/life_special(datum/seq_frame/life/F)
	if(src.stat != DEAD)
		src.heal_aura()
	..()

/mob/living/simple_mob/slime/xenobio/pink/proc/heal_aura()
	for(var/mob/living/L in view(src, 2))
		if(L.stat == DEAD || !IIsAlly(L))
			continue
		L.apply_body_effect(/datum/body_effect/aura/slime_heal, null, src)

// A pacified pink slime for either Admin-spawning or putting in a casino reward or capture crystal.
/mob/living/simple_mob/slime/xenobio/pink/sana
	name = "Sana"
	desc = "A pink slime that seems to be oddly friendly, and doesn't seem interested in eating your face like the rest of them."
	rainbow_core_candidate = FALSE

CAPABILITIES(/mob/living/simple_mob/slime/xenobio/pink/sana)
	configure(mob_rules(faction = FACTION_NEUTRAL))

/mob/living/simple_mob/slime/xenobio/pink/sana
	// born pacified (what pacify() sets on the mob; the slime base's update_mood() at init takes its mood and vore settings from it)
	harmless = TRUE
	melee_damage_upper = 0
	melee_damage_lower = 0
